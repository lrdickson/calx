package kernel

import (
	"fmt"
	"go/build"
	"log"
	"os"
	"reflect"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/traefik/yaegi/interp"
	"github.com/traefik/yaegi/stdlib"
)

const (
	ok int = iota
	failed
)

type workerStatus struct {
	name  string
	value int
}

type worker struct {
	active    atomic.Bool
	formula   Formula
	name      string
	quit      chan int
	result    any
	runSignal chan int
	wait      sync.WaitGroup
}

type Formula struct {
	Dependencies []string
	Code         string
}

type Kernel struct {
	workers map[string]*worker
	status  chan workerStatus
}

func (k *Kernel) stop(name string) {
	if _, exists := k.workers[name]; exists {
		if k.workers[name].active.Load() {
			k.workers[name].quit <- 0
		}
	}
}

func (k *Kernel) getActiveCount() int {
	activeCount := 0
	for name := range k.workers {
		if k.workers[name].active.Load() {
			activeCount++
		}
	}
	return activeCount
}

func (k *Kernel) runWorkers() {
	for _, w := range k.workers {
		w.wait.Add(1)
	}

	for _, w := range k.workers {
		log.Println("Starting:", w.name)
		inputSent := false
		for {
			if w.active.Load() {
				select {
				case w.runSignal <- 0:
					log.Println("Input sent to:", w.name)
					inputSent = true
				default:
					//log.Println(w.name, "not ready")
					time.Sleep(time.Millisecond)
				}
			} else {
				break
			}

			// escape if input sent
			if inputSent {
				break
			}
		}
	}

}

func NewKernel() *Kernel {
	// Make the kernel
	status := make(chan workerStatus)
	k := &Kernel{
		workers: make(map[string]*worker),
		status:  status,
	}

	// Watch for errors
	go func() {
		for {
			ws := <-status
			log.Println(ws.name, "quit with status", ws.value)
			k.workers[ws.name].active.Store(false)
			if ws.value != ok {
				k.workers[ws.name].wait.Done()
			}
		}
	}()

	return k
}

func (k *Kernel) addWorker(name string, formula Formula, done chan string) {
	// Stop the worker if it already existed
	k.stop(name)

	// Create a new worker
	log.Println("Creating new worker:", name)
	quit := make(chan int)
	run := make(chan int)
	newWorker := worker{
		quit:      quit,
		runSignal: run,
		name:      name,
		formula:   formula,
	}
	newWorker.active.Store(true)
	k.workers[name] = &newWorker

	// Start the new worker
	go func() {
		// Start the interpreter
		gointerp := interp.New(interp.Options{
			GoPath: build.Default.GOPATH,
			Env:    os.Environ(),
			//Unrestricted: true,
		})
		if err := gointerp.Use(stdlib.Symbols); err != nil {
			log.Fatal("Stdlib load error:", err)
		}
		if err := gointerp.Use(interp.Symbols); err != nil {
			log.Fatal("Interp symbol load error:", err)
		}

		for {
			log.Println(newWorker.name, "ready to receive commands")
			select {
			case <-quit:
				log.Println("Quiting:", newWorker.name)
				k.status <- workerStatus{newWorker.name, ok}
				return
			//case params := <-in:
			case <-run:
				// Build the function code
				functionCode := "package run\n"
				functionCode += `import . "math"` + "\n"
				functionCode += "func Run(params []any) any {\n"

				// Get the function parameters
				params := make([]any, 0, len(formula.Dependencies))
				for index, dependency := range formula.Dependencies {
					// Get the result
					dependentWorker, exists := k.workers[dependency]
					if !exists {
						log.Println(newWorker.name, "dependent worker", dependentWorker, "doesn't exist")
						k.status <- workerStatus{newWorker.name, failed}
						return
					}
					dependentWorker.wait.Wait()
					params = append(params, dependentWorker.result)

					// Determine the type
					functionCode += dependency + " := params[" + strconv.Itoa(index) + "]"
					if dependentWorker.result != nil {
						paramType := reflect.TypeOf(dependentWorker.result)
						functionCode += ".(" + paramType.String() + ")"
					}
					functionCode += "\n"
				}

				// Add in the function code
				functionCode += formula.Code
				functionCode += "}"

				// Create the function
				log.Println("Function code:\n", functionCode)
				_, err := gointerp.Eval(functionCode)
				if err != nil {
					// TODO: Display this error to the user
					log.Println("Failed to evaluate", name, "code:", err)
					k.status <- workerStatus{newWorker.name, failed}
					return
				}
				v, err := gointerp.Eval("run.Run")
				if err != nil {
					log.Println("Failed to get", newWorker.name, "function:", err)
					k.status <- workerStatus{newWorker.name, failed}
					return
				}
				function := v.Interface().(func([]any) any)

				// Get the function output
				log.Println(newWorker.name, "running function")
				newWorker.result = func() (result any) {
					defer func() {
						if r := recover(); r != nil {
							// TODO: Display this error to the user
							log.Println("Recoverd from yaegi panic:", r)
							result = r
							return
						}
					}()
					return function(params)
				}()
				log.Println(newWorker.name, "function returned result", newWorker.result)
				newWorker.wait.Done()
				done <- newWorker.name
			}
		}
	}()
}

func (k *Kernel) getWorker(name string) (*worker, bool) {
	if formulaWorker, exists := k.workers[name]; exists {
		return formulaWorker, formulaWorker.active.Load()
	}
	return nil, false
}

func (k *Kernel) RenameFormula(oldName, newName string) {
	if formulaWorker, exists := k.workers[oldName]; exists {
		if formulaWorker.active.Load() {
			formulaWorker.name = newName
		}
		k.workers[newName] = formulaWorker
		delete(k.workers, oldName)
	}
}

func (k *Kernel) Update(workerFormulas map[string]*Formula) map[string]string {
	// Make a worker for each formula provided
	done := make(chan string)
	for name, formula := range workerFormulas {
		k.addWorker(name, *formula, done)
	}

	// Run all of the workers
	k.runWorkers()

	// Get the output
	outputData := make(map[string]string)
	responseReceived := make(map[string]bool)
	for {
		select {
		case name := <-done:
			// Get the worker
			log.Println("Sending quit signal to:", name)
			activeWorker, workerExists := k.workers[name]
			if !workerExists {
				break
			}

			// Stop the worker
			// TODO: rename workers and leave them running
			k.stop(name)
			log.Println("quit signal sent to:", name)

			// Interpet the data
			result := activeWorker.result
			switch result.(type) {
			case bool:
				outputData[name] = strconv.FormatBool(result.(bool))
			case int:
				outputData[name] = strconv.Itoa(result.(int))
			case uint:
				outputData[name] = strconv.FormatUint(uint64(result.(uint)), 10)
			case float32:
				outputData[name] = strconv.FormatFloat(float64(result.(float32)), 'f', -1, 32)
			case float64:
				outputData[name] = strconv.FormatFloat(result.(float64), 'f', -1, 64)
			case string:
				outputData[name] = result.(string)
			default:
				outputReflect := reflect.ValueOf(result)
				outputData[name] = fmt.Sprintf("%v", outputReflect)
			}
			responseReceived[name] = true
		case <-time.After(time.Millisecond):
			//log.Println("timeout")
		}
		if k.getActiveCount() == 0 {
			break
		}
		//log.Println("Workers are still active")
	}
	return outputData
}
