# Ollama Model Optimizer for Windows PowerShell
# Automatically selects and configures optimal coding models based on system resources

# Requires PowerShell 5.0 or later
#Requires -Version 5.0

# Set strict mode for better error handling
Set-StrictMode -Version Latest

# Color functions for output
function Write-ColorOutput {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

Write-ColorOutput "==================================" "Cyan"
Write-ColorOutput "  Ollama Model Optimizer for Windows" "Cyan"
Write-ColorOutput "==================================" "Cyan"
Write-Host ""

# Function to get system information
function Get-SystemInfo {
    Write-ColorOutput "System Information:" "Green"
    
    # Get CPU information
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $cpuName = $cpu.Name
    Write-Host "  CPU: $cpuName"
    
    # Get total RAM in GB
    $totalRam = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
    $script:totalRamGB = [math]::Round($totalRam / 1GB)
    Write-Host "  Total RAM: $($script:totalRamGB)GB"
    
    # Get GPU information
    $gpus = Get-CimInstance -ClassName Win32_VideoController
    $script:vramGB = 0
    $script:gpuType = "Unknown"
    $script:hasNvidiaGPU = $false
    $script:hasAmdGPU = $false
    
    foreach ($gpu in $gpus) {
        if ($gpu.Name -like "*NVIDIA*") {
            $script:hasNvidiaGPU = $true
            $script:gpuType = $gpu.Name
            
            # Try to get VRAM using NVIDIA SMI if available
            # Check multiple possible locations for nvidia-smi
            $nvidiaSmiPaths = @(
                "$env:SystemRoot\System32\nvidia-smi.exe",
                "${env:ProgramFiles}\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
            )
            
            $vramDetected = $false
            foreach ($nvidiaSmiPath in $nvidiaSmiPaths) {
                if (Test-Path $nvidiaSmiPath) {
                    try {
                        # Use csv format and parse the output (format: "24576 MiB")
                        $smiOutput = & $nvidiaSmiPath --query-gpu=memory.total --format=csv 2>$null | Select-Object -Skip 1
                        if ($smiOutput) {
                            $smiOutput = $smiOutput.Trim()
                            # Parse format like "24576 MiB"
                            if ($smiOutput -match '(\d+)\s*MiB') {
                                $vramMiB = [int]$matches[1]
                                $script:vramGB = [math]::Round($vramMiB / 1024, 0)
                                $vramDetected = $true
                                break
                            }
                        }
                    }
                    catch {
                        # Continue to next path
                        continue
                    }
                }
            }
            
            # Fallback to estimates if nvidia-smi didn't work
            if (-not $vramDetected) {
                if ($gpu.AdapterRAM -gt 0) {
                    $script:vramGB = [math]::Round($gpu.AdapterRAM / 1GB)
                }
                else {
                    # Common VRAM sizes for NVIDIA GPUs
                    if ($gpu.Name -like "*RTX 4090*") { $script:vramGB = 24 }
                    elseif ($gpu.Name -like "*RTX 4080*") { $script:vramGB = 16 }
                    elseif ($gpu.Name -like "*RTX 4070*") { $script:vramGB = 12 }
                    elseif ($gpu.Name -like "*RTX 4060*") { $script:vramGB = 8 }
                    elseif ($gpu.Name -like "*RTX 3090*") { $script:vramGB = 24 }
                    elseif ($gpu.Name -like "*RTX 3080*") { $script:vramGB = 10 }
                    elseif ($gpu.Name -like "*RTX 3070*") { $script:vramGB = 8 }
                    elseif ($gpu.Name -like "*RTX 3060*") { $script:vramGB = 12 }
                    else { $script:vramGB = 6 } # Conservative estimate
                }
            }
            break
        }
        elseif ($gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
            $script:hasAmdGPU = $true
            $script:gpuType = $gpu.Name
            
            # Estimate VRAM for AMD GPUs
            if ($gpu.AdapterRAM -gt 0) {
                $script:vramGB = [math]::Round($gpu.AdapterRAM / 1GB)
            }
            else {
                # Common VRAM sizes for AMD GPUs
                if ($gpu.Name -like "*RX 7900*") { $script:vramGB = 24 }
                elseif ($gpu.Name -like "*RX 7800*") { $script:vramGB = 16 }
                elseif ($gpu.Name -like "*RX 7700*") { $script:vramGB = 12 }
                elseif ($gpu.Name -like "*RX 7600*") { $script:vramGB = 8 }
                elseif ($gpu.Name -like "*RX 6900*") { $script:vramGB = 16 }
                elseif ($gpu.Name -like "*RX 6800*") { $script:vramGB = 16 }
                elseif ($gpu.Name -like "*RX 6700*") { $script:vramGB = 12 }
                elseif ($gpu.Name -like "*RX 6600*") { $script:vramGB = 8 }
                else { $script:vramGB = 4 } # Conservative estimate
            }
            break
        }
        elseif ($gpu.Name -like "*Intel*") {
            $script:gpuType = $gpu.Name
            
            # Intel Arc GPUs
            if ($gpu.Name -like "*Arc*") {
                if ($gpu.Name -like "*A770*") { $script:vramGB = 16 }
                elseif ($gpu.Name -like "*A750*") { $script:vramGB = 8 }
                elseif ($gpu.Name -like "*A380*") { $script:vramGB = 6 }
                else { $script:vramGB = 4 }
            }
            else {
                # Integrated graphics
                $script:vramGB = 2
            }
        }
    }
    
    if ($script:vramGB -eq 0) {
        $script:vramGB = 2  # Fallback for integrated graphics
        $script:gpuType = "Integrated Graphics"
    }
    
    Write-Host "  GPU: $($script:gpuType)"
    Write-Host "  Estimated VRAM: $($script:vramGB)GB"
    
    if ($script:hasNvidiaGPU) {
        Write-ColorOutput "  CUDA acceleration available" "Yellow"
    }
    
    Write-Host ""
}

# Function to calculate available memory for models
function Get-AvailableMemory {
    # Reserve memory for system and applications
    $systemReserveGB = 4
    
    $script:availableRamGB = [math]::Max(0, $script:totalRamGB - $systemReserveGB)
    $script:availableVramGB = $script:vramGB
    
    # The limiting factor
    if ($script:availableVramGB -lt $script:availableRamGB) {
        $script:maxModelSizeGB = $script:availableVramGB
    }
    else {
        $script:maxModelSizeGB = $script:availableRamGB
    }
    
    Write-ColorOutput "Available Resources for Models:" "Green"
    Write-Host "  Usable RAM: $($script:availableRamGB)GB"
    Write-Host "  Usable VRAM: $($script:availableVramGB)GB"
    Write-Host "  Max Model Size: $($script:maxModelSizeGB)GB"
    Write-Host ""
}

# Function to recommend models based on available resources
function Get-ModelRecommendations {
    Write-ColorOutput "Recommended Models for Coding:" "Green"
    Write-Host ""
    
    # Model configurations: name, min_gb, recommended_gb, context, description
    $models = @(
        @{Name = "qwen2.5-coder:32b-instruct-q4_K_M"; MinGB = 20; RecGB = 24; Context = 32768; Desc = "Excellent 32B coding model with Q4 quantization" },
        @{Name = "qwen2.5-coder:14b-instruct-q5_K_M"; MinGB = 12; RecGB = 16; Context = 32768; Desc = "Great 14B coding model with Q5 quantization" },
        @{Name = "qwen2.5-coder:7b-instruct-q8_0"; MinGB = 8; RecGB = 10; Context = 32768; Desc = "Solid 7B model with high quality Q8 quantization" },
        @{Name = "qwen2.5-coder:7b-instruct-q5_K_M"; MinGB = 5; RecGB = 6; Context = 32768; Desc = "Efficient 7B model with Q5 quantization" },
        @{Name = "deepseek-coder-v2:16b-lite-instruct-q4_K_M"; MinGB = 10; RecGB = 12; Context = 16384; Desc = "DeepSeek 16B lightweight version" },
        @{Name = "codellama:34b-instruct-q4_K_M"; MinGB = 20; RecGB = 24; Context = 16384; Desc = "Meta's 34B CodeLlama with Q4 quantization" },
        @{Name = "codellama:13b-instruct-q5_K_M"; MinGB = 10; RecGB = 12; Context = 16384; Desc = "Meta's 13B CodeLlama with Q5 quantization" },
        @{Name = "codellama:7b-instruct-q8_0"; MinGB = 8; RecGB = 10; Context = 16384; Desc = "Meta's 7B CodeLlama with high quality" },
        @{Name = "starcoder2:15b-q4_K_M"; MinGB = 10; RecGB = 12; Context = 16384; Desc = "StarCoder2 15B for code completion" },
        @{Name = "starcoder2:7b-q5_K_M"; MinGB = 5; RecGB = 6; Context = 16384; Desc = "StarCoder2 7B efficient version" },
        @{Name = "codegemma:7b-instruct-q5_K_M"; MinGB = 5; RecGB = 6; Context = 8192; Desc = "Google's CodeGemma 7B" },
        @{Name = "granite-code:8b-instruct-q4_K_M"; MinGB = 5; RecGB = 6; Context = 8192; Desc = "IBM Granite Code 8B" },
        @{Name = "stable-code:3b-q8_0"; MinGB = 3; RecGB = 4; Context = 16384; Desc = "Stability AI's compact 3B model" }
    )
    
    # Initialize script-level arrays to store models
    $script:recommendedModels = @()
    $script:possibleModels = @()
    $recommendedCount = 0
    $possibleCount = 0
    
    Write-ColorOutput "Optimal Choices:" "Cyan"
    foreach ($model in $models) {
        if ($script:maxModelSizeGB -ge $model.RecGB) {
            Write-ColorOutput "  [OK] $($model.Name)" "Green"
            Write-Host "     Memory: $($model.RecGB)GB | Context: $($model.Context) tokens"
            Write-Host "     $($model.Desc)"
            
            # Suggest optimal context window based on available RAM
            if ($script:availableRamGB -ge ($model.RecGB + 4)) {
                Write-ColorOutput "     Recommended settings:" "Yellow"
                Write-Host "     ollama run $($model.Name)"
                Write-Host "     Can use full $($model.Context) token context"
            }
            else {
                $adjustedContext = [math]::Floor($model.Context / 2)
                Write-ColorOutput "     Recommended settings:" "Yellow"
                Write-Host "     ollama run $($model.Name)"
                Write-Host "     Consider reducing context to $adjustedContext tokens if OOM"
            }
            Write-Host ""
            $recommendedCount++
            $script:recommendedModels += $model
        }
    }
    
    if ($recommendedCount -eq 0) {
        Write-ColorOutput "  No optimal models for your configuration" "Yellow"
        Write-Host ""
    }
    
    Write-ColorOutput "Possible with Reduced Performance:" "Cyan"
    foreach ($model in $models) {
        if (($script:maxModelSizeGB -ge $model.MinGB) -and ($script:maxModelSizeGB -lt $model.RecGB)) {
            Write-ColorOutput "  [WARNING] $($model.Name)" "Yellow"
            Write-Host "     Minimum: $($model.MinGB)GB | Recommended: $($model.RecGB)GB"
            Write-Host "     $($model.Desc)"
            
            # Calculate reduced context window
            $reductionFactor = $script:maxModelSizeGB / $model.RecGB
            $adjustedContext = [math]::Floor($model.Context * $reductionFactor)
            
            Write-ColorOutput "     Adjusted settings:" "Yellow"
            Write-Host "     Reduce context to ~$adjustedContext tokens"
            Write-Host "     May experience slower performance"
            Write-Host ""
            $possibleCount++
            $script:possibleModels += $model
        }
    }
    
    if (($possibleCount -eq 0) -and ($recommendedCount -eq 0)) {
        Write-ColorOutput "  [X] Your system ($($script:maxModelSizeGB)GB available) may struggle with larger models" "Red"
        Write-Host "     Consider these lightweight options:"
        Write-Host "     - stable-code:3b (3GB minimum)"
        Write-Host "     - codegemma:2b (2GB minimum)"
        Write-Host ""
    }
}

# Function to create optimized Modelfile
function New-OptimizedModelfile {
    param(
        [string]$BaseModel,
        [int]$ContextSize
    )
    
    $outputFile = "Modelfile.optimized"
    
    $modelfileContent = @"
# Optimized Modelfile for $BaseModel
FROM $BaseModel

# Optimized parameters based on system resources
PARAMETER num_ctx $ContextSize
PARAMETER num_batch 512
PARAMETER num_gpu 999  # Use all available GPU layers
PARAMETER num_thread 8

# Temperature for coding (more deterministic)
PARAMETER temperature 0.2
PARAMETER top_p 0.95
PARAMETER top_k 40

# System prompt for coding
SYSTEM """You are an expert programming assistant. Provide clear, concise, and well-commented code. Follow best practices and explain your solutions when needed."""
"@

    Set-Content -Path $outputFile -Value $modelfileContent
    
    Write-ColorOutput "Created optimized Modelfile: $outputFile" "Green"
    Write-Host "To use: ollama create my-optimized-model -f $outputFile"
}

# Function to get installed Ollama models
function Get-InstalledModels {
    try {
        $output = & ollama list 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            # Parse the output to get model names (skip header line)
            $lines = $output -split "`n" | Select-Object -Skip 1
            $installedModels = @()
            foreach ($line in $lines) {
                if ($line.Trim() -and $line -match '^\s*(\S+)') {
                    $installedModels += $matches[1]
                }
            }
            return $installedModels
        }
    }
    catch {
        Write-ColorOutput "Warning: Could not retrieve installed models" "Yellow"
    }
    return @()
}

# Function to check if aider is installed
function Test-AiderInstallation {
    try {
        $null = Get-Command aider -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Function to install aider
function Install-Aider {
    Write-Host ""
    Write-ColorOutput "Installing aider..." "Yellow"
    Write-Host "Aider requires Python and pip to be installed."
    Write-Host ""
    
    try {
        # Check if pip is available
        $null = Get-Command pip -ErrorAction Stop
        
        Write-Host "Installing aider-chat via pip..."
        & pip install aider-chat
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Aider installed successfully!" "Green"
            return $true
        }
        else {
            Write-ColorOutput "Failed to install aider" "Red"
            return $false
        }
    }
    catch {
        Write-ColorOutput "Python/pip not found. Please install Python first:" "Red"
        Write-Host "Download from: https://www.python.org/downloads/"
        Write-Host "Make sure to check 'Add Python to PATH' during installation"
        return $false
    }
}

# Function to launch aider with selected model
function Invoke-AiderWithModel {
    param(
        [string]$ModelName
    )
    
    Write-Host ""
    $aiderResponse = Read-Host "Would you like to launch aider with this model? (y/n)"
    
    if ($aiderResponse -ne 'y' -and $aiderResponse -ne 'Y') {
        return
    }
    
    # Check if aider is installed
    if (-not (Test-AiderInstallation)) {
        Write-ColorOutput "Aider is not installed." "Yellow"
        $installAider = Read-Host "Would you like to install aider now? (y/n)"
        
        if ($installAider -eq 'y' -or $installAider -eq 'Y') {
            if (-not (Install-Aider)) {
                return
            }
        }
        else {
            Write-Host "You can install aider later with: pip install aider-chat"
            return
        }
    }
    
    Write-Host ""
    Write-ColorOutput "Launching aider with $ModelName..." "Green"
    Write-Host ""
    Write-Host "Aider will start in a moment. Press Ctrl+C to exit aider when done."
    Write-Host ""
    
    # Launch aider with the selected model
    & aider --model "ollama/$ModelName"
}

# Function to install and pull recommended model with menu
function Install-RecommendedModel {
    Write-Host ""
    Write-ColorOutput "Model Installation:" "Cyan"
    
    # Check for already installed models
    $installedModels = Get-InstalledModels
    $installedRecommended = @()
    
    foreach ($model in $script:recommendedModels) {
        if ($installedModels -contains $model.Name) {
            $installedRecommended += $model
        }
    }
    
    # Show already installed models if any
    if ($installedRecommended.Count -gt 0) {
        Write-ColorOutput "Already installed optimal models:" "Green"
        for ($i = 0; $i -lt $installedRecommended.Count; $i++) {
            Write-Host "  [$($i + 1)] $($installedRecommended[$i].Name) - $($installedRecommended[$i].RecGB)GB"
        }
        Write-Host ""
        
        $useExisting = Read-Host "Use an already installed model? (y/n)"
        if ($useExisting -eq 'y' -or $useExisting -eq 'Y') {
            if ($installedRecommended.Count -eq 1) {
                $selectedModel = $installedRecommended[0]
            }
            else {
                $selection = Read-Host "Select model number (1-$($installedRecommended.Count))"
                $index = [int]$selection - 1
                if ($index -ge 0 -and $index -lt $installedRecommended.Count) {
                    $selectedModel = $installedRecommended[$index]
                }
                else {
                    Write-ColorOutput "Invalid selection" "Red"
                    return
                }
            }
            
            Write-Host ""
            Write-ColorOutput "Selected: $($selectedModel.Name)" "Green"
            Invoke-AiderWithModel -ModelName $selectedModel.Name
            return
        }
    }
    
    # Offer to install a new model
    $response = Read-Host "Would you like to install a new model? (y/n)"
    
    if ($response -ne 'y' -and $response -ne 'Y') {
        return
    }
    
    # Combine all models for menu
    $allModels = @()
    $allModels += $script:recommendedModels
    $allModels += $script:possibleModels
    
    if ($allModels.Count -eq 0) {
        Write-ColorOutput "No models available for your system configuration" "Red"
        return
    }
    
    # Display menu
    Write-Host ""
    Write-ColorOutput "Select a model to install:" "Cyan"
    Write-Host ""
    
    for ($i = 0; $i -lt $allModels.Count; $i++) {
        $model = $allModels[$i]
        $isOptimal = $i -lt $script:recommendedModels.Count
        $status = if ($isOptimal) { "[OPTIMAL]" } else { "[REDUCED]" }
        $color = if ($isOptimal) { "Green" } else { "Yellow" }
        
        Write-ColorOutput "  [$($i + 1)] $status $($model.Name)" $color
        Write-Host "      Memory: $($model.RecGB)GB | Context: $($model.Context) tokens"
    }
    
    Write-Host ""
    Write-Host "  [0] Enter custom model name"
    Write-Host ""
    
    $selection = Read-Host "Select model number (0-$($allModels.Count))"
    
    $modelName = $null
    $selectedModel = $null
    
    if ($selection -eq '0') {
        $modelName = Read-Host "Enter custom model name (e.g., qwen2.5-coder:7b-instruct-q5_K_M)"
    }
    else {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $allModels.Count) {
            $selectedModel = $allModels[$index]
            $modelName = $selectedModel.Name
        }
        else {
            Write-ColorOutput "Invalid selection" "Red"
            return
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($modelName)) {
        Write-ColorOutput "No model selected" "Red"
        return
    }
    
    # Pull the model
    Write-Host ""
    Write-ColorOutput "Pulling $modelName..." "Yellow"
    Write-Host "This may take several minutes depending on model size and connection speed..."
    Write-Host ""
    
    & ollama pull $modelName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-ColorOutput "Model installed successfully!" "Green"
        Write-ColorOutput "Run with: ollama run $modelName" "Cyan"
        
        # Offer to create optimized Modelfile
        Write-Host ""
        $optimizeResponse = Read-Host "Create an optimized Modelfile? (y/n)"
        
        if ($optimizeResponse -eq 'y' -or $optimizeResponse -eq 'Y') {
            if ($selectedModel) {
                New-OptimizedModelfile -BaseModel $modelName -ContextSize $selectedModel.Context
            }
            else {
                $contextSize = Read-Host "Enter context size (e.g., 16384)"
                New-OptimizedModelfile -BaseModel $modelName -ContextSize $contextSize
            }
        }
        
        # Offer to launch aider
        Invoke-AiderWithModel -ModelName $modelName
    }
    else {
        Write-ColorOutput "Failed to install model" "Red"
    }
}

# Function to check if Ollama is installed
function Test-OllamaInstallation {
    try {
        $ollamaPath = Get-Command ollama -ErrorAction Stop
        return $true
    }
    catch {
        Write-ColorOutput "Ollama is not installed or not in PATH!" "Red"
        Write-Host "Install it from: https://ollama.ai/download"
        Write-Host ""
        Write-Host "After installation, make sure Ollama is in your PATH:"
        Write-Host "1. Add Ollama installation directory to PATH environment variable"
        Write-Host "2. Restart PowerShell"
        return $false
    }
}

# Function to check if Ollama service is running
function Test-OllamaService {
    try {
        # Try to list models to check if service is running
        $output = & ollama list 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Starting Ollama service..." "Yellow"
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }
        return $true
    }
    catch {
        Write-ColorOutput "Failed to start Ollama service" "Red"
        return $false
    }
}

# Function to display optimization tips
function Show-OptimizationTips {
    Write-Host ""
    Write-ColorOutput "Optimization complete!" "Green"
    Write-ColorOutput "Tips for best performance:" "Cyan"
    Write-Host "  • Close unnecessary applications to free up RAM"
    Write-Host "  • Use quantized models (q4_K_M, q5_K_M) for better memory efficiency"
    Write-Host "  • Adjust context window size if you experience out-of-memory errors"
    Write-Host "  • For coding, models with 'coder' or 'code' in the name perform best"
    
    if ($script:hasNvidiaGPU) {
        Write-Host "  • Your NVIDIA GPU will use CUDA acceleration for better performance"
        Write-Host "  • Ensure you have the latest NVIDIA drivers installed"
    }
    
    if ($script:hasAmdGPU) {
        Write-Host "  • Your AMD GPU can use ROCm acceleration if supported"
        Write-Host "  • Ensure you have the latest AMD drivers installed"
    }
    
    Write-Host ""
    Write-ColorOutput "Advanced Configuration:" "Cyan"
    Write-Host "  Set environment variables for fine-tuning:"
    Write-Host "  • OLLAMA_NUM_GPU=999 (use all GPU layers)"
    Write-Host "  • OLLAMA_MAX_LOADED_MODELS=1 (reduce memory usage)"
    Write-Host "  • OLLAMA_KEEP_ALIVE=5m (keep model in memory for 5 minutes)"
    Write-Host ""
    Write-Host "  To set permanently in PowerShell:"
    Write-Host '  [Environment]::SetEnvironmentVariable("OLLAMA_NUM_GPU", "999", "User")'
}

# Main execution function
function Start-OllamaOptimizer {
    # Check if running as administrator (optional but recommended)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-ColorOutput "Note: Running as administrator may provide more accurate system information" "Yellow"
        Write-Host ""
    }
    
    # Check if Ollama is installed
    if (-not (Test-OllamaInstallation)) {
        return
    }
    
    # Check if Ollama service is running
    if (-not (Test-OllamaService)) {
        return
    }
    
    # Get system information
    Get-SystemInfo
    
    # Calculate available memory
    Get-AvailableMemory
    
    # Get model recommendations
    Get-ModelRecommendations
    
    # Offer to install a model
    Install-RecommendedModel
    
    # Show optimization tips
    Show-OptimizationTips
}

# Error handling wrapper
try {
    Start-OllamaOptimizer
}
catch {
    Write-ColorOutput "An error occurred: $_" "Red"
    Write-Host ""
    Write-Host "Stack trace:"
    Write-Host $_.ScriptStackTrace
}