Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force

# Get-DriverClass is pure and deterministic — classify by title.
Assert-Equal (Get-DriverClass 'Advanced Micro Devices, Inc. Display Driver Update (32.0.21036.18)') 'display' 'driverclass: AMD display -> display'
Assert-Equal (Get-DriverClass 'Razer Inc - Mouse - 6.2.9200.16547') 'input' 'driverclass: Razer mouse -> input'
Assert-Equal (Get-DriverClass 'Microsoft Corporation AudioProcessingObject Driver Update (1.0.4.7057)') 'audio' 'driverclass: audio APO -> audio'
Assert-Equal (Get-DriverClass 'Alienware SoftwareComponent Driver Update (2.7.2.0)') 'other' 'driverclass: SoftwareComponent -> other'
Assert-Equal (Get-DriverClass 'NVIDIA - Graphics Adapter WDDM - 32.0.15.7602') 'display' 'driverclass: NVIDIA graphics -> display'
