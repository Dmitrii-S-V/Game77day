# Import assets/ready/*.glb into the Godot project (assets already live inside the project).
param([string]$Godot = "C:\Godot\godot.exe", [string]$Project = "D:\77Days")
& $Godot --headless --import --path $Project 2>&1 | Select-Object -Last 8
Get-ChildItem "$Project\assets\ready\*.glb" | ForEach-Object {
    $imp = Test-Path "$($_.FullName).import"
    "{0,-30} import-file={1}" -f $_.Name, $imp
}
