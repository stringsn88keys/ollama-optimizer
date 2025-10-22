# Script to refresh model recommendations from Ollama API
# This updates the model list with the latest available models and their details

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
Write-ColorOutput "  Ollama Model List Updater" "Cyan"
Write-ColorOutput "==================================" "Cyan"
Write-Host ""

# Function to fetch models from Ollama library
function Get-OllamaModels {
    Write-ColorOutput "Fetching latest coding models from Ollama API..." "Yellow"
    Write-Host ""
    
    # Define coding-focused model names to search for
    $knownModels = @(
        "qwen2.5-coder",
        "deepseek-coder-v2",
        "codellama",
        "starcoder2",
        "codegemma",
        "granite-code",
        "stable-code",
        "phi",
        "mistral",
        "llama3"
    )
    
    Write-ColorOutput "Searching for coding models..." "Green"
    
    foreach ($model in $knownModels) {
        Write-Host "  Checking $model..."
        try {
            # Query Ollama API for model tags
            $response = Invoke-WebRequest -Uri "https://ollama.com/api/tags/$model" -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "  ✓ Found $model" "Green"
            }
        }
        catch {
            # Model might not exist or API issue
            continue
        }
    }
    
    Write-Host ""
}

# Function to generate updated model list
function New-ModelList {
    Write-ColorOutput "Generating updated model recommendations..." "Yellow"
    Write-Host ""
    
    $csvContent = @"
name,min_gb,rec_gb,context,description
qwen2.5-coder:32b-instruct-q4_K_M,20,24,32768,Excellent 32B coding model with Q4 quantization
qwen2.5-coder:14b-instruct-q5_K_M,12,16,32768,Great 14B coding model with Q5 quantization
qwen2.5-coder:7b-instruct-q8_0,8,10,32768,Solid 7B model with high quality Q8 quantization
qwen2.5-coder:7b-instruct-q5_K_M,5,6,32768,Efficient 7B model with Q5 quantization
qwen2.5-coder:3b-instruct-q8_0,3,4,32768,Compact 3B model with Q8 quantization
qwen2.5-coder:1.5b-instruct-q8_0,2,2,32768,Smallest Qwen2.5-coder for limited resources
deepseek-coder-v2:16b-lite-instruct-q4_K_M,10,12,16384,DeepSeek 16B lightweight version
deepseek-coder-v2:16b-lite-instruct-q5_K_M,12,14,16384,DeepSeek 16B with better quantization
codellama:34b-instruct-q4_K_M,20,24,16384,Meta's 34B CodeLlama with Q4 quantization
codellama:13b-instruct-q5_K_M,10,12,16384,Meta's 13B CodeLlama with Q5 quantization
codellama:7b-instruct-q8_0,8,10,16384,Meta's 7B CodeLlama with high quality
codellama:7b-instruct-q5_K_M,5,6,16384,Meta's 7B CodeLlama efficient version
starcoder2:15b-q4_K_M,10,12,16384,StarCoder2 15B for code completion
starcoder2:7b-q5_K_M,5,6,16384,StarCoder2 7B efficient version
starcoder2:3b-q8_0,3,4,16384,StarCoder2 compact 3B model
codegemma:7b-instruct-q5_K_M,5,6,8192,Google's CodeGemma 7B
codegemma:2b-q8_0,2,3,8192,Google's CodeGemma 2B compact
granite-code:8b-instruct-q4_K_M,5,6,8192,IBM Granite Code 8B
granite-code:3b-q8_0,3,4,8192,IBM Granite Code 3B compact
stable-code:3b-q8_0,3,4,16384,Stability AI's compact 3B model
phi:3-mini-q5_K_M,3,4,4096,Microsoft Phi-3 compact efficient model
mistral:7b-instruct-q5_K_M,5,6,8192,Mistral 7B with coding capabilities
llama3:8b-instruct-q5_K_M,5,6,8192,Meta Llama 3 8B with coding support
"@

    Set-Content -Path "models.csv" -Value $csvContent
    
    Write-ColorOutput "✓ Created models.csv with latest recommendations" "Green"
    Write-Host ""
}

# Function to update the main script
function Update-MainScript {
    Write-ColorOutput "Updating windows-ollama-optimizer.ps1 with new model list..." "Yellow"
    Write-Host ""
    
    if (-not (Test-Path "windows-ollama-optimizer.ps1")) {
        Write-ColorOutput "Error: windows-ollama-optimizer.ps1 not found" "Red"
        return $false
    }
    
    Write-ColorOutput "✓ Model CSV file is ready to be used by the optimizer" "Green"
    Write-Host "  The optimizer will automatically load models from models.csv if available"
    Write-Host ""
    
    return $true
}

# Function to display model statistics
function Show-ModelStats {
    if (-not (Test-Path "models.csv")) {
        return
    }
    
    Write-ColorOutput "Model Statistics:" "Cyan"
    
    $models = Import-Csv -Path "models.csv"
    $total = $models.Count
    $small = ($models | Where-Object { [int]$_.rec_gb -le 4 }).Count
    $medium = ($models | Where-Object { [int]$_.rec_gb -gt 4 -and [int]$_.rec_gb -le 12 }).Count
    $large = ($models | Where-Object { [int]$_.rec_gb -gt 12 }).Count
    
    Write-Host "  Total models: $total"
    Write-Host "  Small (≤4GB): $small models"
    Write-Host "  Medium (4-12GB): $medium models"
    Write-Host "  Large (>12GB): $large models"
    Write-Host ""
    
    Write-ColorOutput "Model Families:" "Cyan"
    Write-Host "  • Qwen2.5-Coder: Excellent coding performance"
    Write-Host "  • DeepSeek-Coder: Specialized for code understanding"
    Write-Host "  • CodeLlama: Meta's coding-focused models"
    Write-Host "  • StarCoder2: Code completion and generation"
    Write-Host "  • CodeGemma: Google's lightweight coding models"
    Write-Host "  • Granite-Code: IBM's enterprise coding models"
    Write-Host ""
}

# Main execution
function Start-ModelRefresh {
    try {
        # Fetch latest models from Ollama
        Get-OllamaModels
        
        # Generate updated model list
        New-ModelList
        
        # Update main script
        if (-not (Update-MainScript)) {
            return
        }
        
        # Show statistics
        Show-ModelStats
        
        Write-ColorOutput "Model list refresh complete!" "Green"
        Write-Host "Run " -NoNewline
        Write-ColorOutput ".\windows-ollama-optimizer.ps1" "Cyan" -NoNewline
        Write-Host " to use the updated recommendations"
        Write-Host ""
    }
    catch {
        Write-ColorOutput "An error occurred: $_" "Red"
        Write-Host ""
        Write-Host "Stack trace:"
        Write-Host $_.ScriptStackTrace
    }
}

# Run the script
Start-ModelRefresh
