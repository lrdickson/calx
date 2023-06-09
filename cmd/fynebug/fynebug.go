package main

import (
	"log"
	"strconv"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/data/binding"
	"fyne.io/fyne/v2/widget"
)

type formulaInfo struct {
	code   binding.String
	name   binding.String
	output binding.String
}

func checkErrFatal(message string, err error) {
	if err != nil {
		log.Fatal(message, err)
	}
}

func getVariable(variables binding.UntypedList, id widget.ListItemID) formulaInfo {
	variablesInterface, err := variables.Get()
	checkErrFatal("Failed to get variable interface array:", err)
	return variablesInterface[id].(formulaInfo)
}

func NewMainView() *container.Split {

	// Create the editor
	variableEditor := widget.NewMultiLineEntry()
	variableEditor.SetPlaceHolder("Enter text...")

	// Display the output
	variables := binding.NewUntypedList()
	variableList := widget.NewListWithData(
		variables,
		func() fyne.CanvasObject {
			nameDisplay := widget.NewLabel("")
			nameEditor := widget.NewEntry()
			nameEditor.Hide()
			editNameButton := widget.NewButton("Edit", func() {})
			editNameButton.OnTapped = func() {
				if nameDisplay.Visible() {
					nameDisplay.Hide()
					nameEditor.Show()
					editNameButton.SetText("Update")
				} else {
					nameDisplay.Show()
					nameEditor.Hide()
					editNameButton.SetText("Edit")
				}
			}
			name := container.NewBorder(nil, nil, nil, editNameButton, container.NewMax(nameDisplay, nameEditor))
			output := widget.NewLabel("Output")
			return container.NewBorder(name, nil, nil, nil, output)
		},
		func(item binding.DataItem, obj fyne.CanvasObject) {
			// Get the variable
			v, err := item.(binding.Untyped).Get()
			checkErrFatal("Failed to get variable data:", err)
			variable := v.(formulaInfo)

			// Set the output
			output := obj.(*fyne.Container).Objects[0].(*widget.Label)
			output.Bind(variable.output)
			output.Refresh()

			// Set the name
			name := obj.(*fyne.Container).Objects[1].(*fyne.Container).Objects[0].(*fyne.Container)
			nameLabel := name.Objects[0].(*widget.Label)
			nameLabel.Bind(variable.name)
			nameEntry := name.Objects[1].(*widget.Entry)
			nameEntry.Bind(variable.name)
			name.Refresh()
		})

	// Create a new variable
	variableCount := 1
	newVariable := func() {
		// Add the variable name
		name := binding.NewString()
		name.Set("NewVariable" + strconv.Itoa(variableCount))
		variableCount++

		// Build the variable
		code := binding.NewString()
		output := binding.NewString()
		newVariable := formulaInfo{code, name, output}
		variables.Append(newVariable)
	}
	newVariableButton := widget.NewButton("New", newVariable)
	for i := 0; i < 1000; i++ {
		newVariable()
	}

	// Edit the code of the selected variable
	variableList.OnSelected = func(id widget.ListItemID) {
		// Assign the code to the editor
		code := getVariable(variables, id).code
		variableEditor.Bind(code)
	}

	// Put everything together
	content := container.NewHSplit(
		container.NewBorder(nil, newVariableButton, nil, nil, variableList),
		container.NewBorder(nil, nil, nil, nil, variableEditor))

	return content
}

func main() {
	// Start the GUI
	mainApp := app.New()
	mainWindow := mainApp.NewWindow("SSGO")
	mainWindow.SetContent(NewMainView())
	mainWindow.Resize(fyne.NewSize(480, 360))
	mainWindow.ShowAndRun()
}
