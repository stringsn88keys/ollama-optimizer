#!/bin/bash

# Ollama Model Optimizer for macOS
# Automatically selects and configures optimal coding models based on system resources

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  Ollama Model Optimizer for macOS${NC}"
echo -e "${BLUE}==================================${NC}\n"

# Function to get system information
get_system_info() {
    echo -e "${GREEN}System Information:${NC}"

    # Get CPU information
    CHIP_TYPE=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    echo -e "  CPU: $CHIP_TYPE"

    # Get total RAM in GB
    TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
    TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1073741824))
    echo -e "  Total RAM: ${TOTAL_RAM_GB}GB"

    # Initialize GPU variables
    VRAM_GB=0
    GPU_TYPE="Unknown"
    HAS_NVIDIA_GPU=false
    HAS_AMD_GPU=false
    IS_APPLE_SILICON=false

    # Check for Apple Silicon
    if [[ "$CHIP_TYPE" == *"Apple"* ]]; then
        # Apple Silicon unified memory
        VRAM_GB=$TOTAL_RAM_GB
        GPU_TYPE="Apple Silicon (Unified Memory)"
        IS_APPLE_SILICON=true
    else
        # Intel Mac - check for discrete GPU
        GPU_DATA=$(system_profiler SPDisplaysDataType 2>/dev/null)

        # Check for NVIDIA GPU
        if echo "$GPU_DATA" | grep -qi "NVIDIA"; then
            HAS_NVIDIA_GPU=true
            GPU_TYPE=$(echo "$GPU_DATA" | grep "Chipset Model" | grep -i nvidia | head -1 | cut -d: -f2 | xargs)

            # Try to get VRAM using nvidia-smi if available
            VRAM_DETECTED=false
            if command -v nvidia-smi &> /dev/null; then
                VRAM_OUTPUT=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
                if [[ -n "$VRAM_OUTPUT" ]] && [[ "$VRAM_OUTPUT" =~ ^[0-9]+$ ]]; then
                    VRAM_GB=$(( (VRAM_OUTPUT + 512) / 1024 ))  # Convert MiB to GiB with rounding
                    VRAM_DETECTED=true
                fi
            fi

            # Fallback VRAM estimates for NVIDIA GPUs if nvidia-smi didn't work
            if [ "$VRAM_DETECTED" = false ]; then
                case "$GPU_TYPE" in
                    *"RTX 4090"*) VRAM_GB=24 ;;
                    *"RTX 4080"*) VRAM_GB=16 ;;
                    *"RTX 4070"*) VRAM_GB=12 ;;
                    *"RTX 4060"*) VRAM_GB=8 ;;
                    *"RTX 3090"*) VRAM_GB=24 ;;
                    *"RTX 3080"*) VRAM_GB=10 ;;
                    *"RTX 3070"*) VRAM_GB=8 ;;
                    *"RTX 3060"*) VRAM_GB=12 ;;
                    *"GTX 1660"*) VRAM_GB=6 ;;
                    *"GTX 1650"*) VRAM_GB=4 ;;
                    *) VRAM_GB=6 ;;  # Conservative estimate
                esac
            fi

        # Check for AMD GPU
        elif echo "$GPU_DATA" | grep -qi -E "(AMD|Radeon)"; then
            HAS_AMD_GPU=true
            GPU_TYPE=$(echo "$GPU_DATA" | grep "Chipset Model" | grep -i -E "(AMD|Radeon)" | head -1 | cut -d: -f2 | xargs)

            # Estimate VRAM for AMD GPUs
            case "$GPU_TYPE" in
                *"RX 7900"*) VRAM_GB=24 ;;
                *"RX 7800"*) VRAM_GB=16 ;;
                *"RX 7700"*) VRAM_GB=12 ;;
                *"RX 7600"*) VRAM_GB=8 ;;
                *"RX 6900"*) VRAM_GB=16 ;;
                *"RX 6800"*) VRAM_GB=16 ;;
                *"RX 6700"*) VRAM_GB=12 ;;
                *"RX 6600"*) VRAM_GB=8 ;;
                *"RX 580"*) VRAM_GB=8 ;;
                *"RX 570"*) VRAM_GB=4 ;;
                *) VRAM_GB=4 ;;  # Conservative estimate
            esac

        # Check for Intel GPU
        elif echo "$GPU_DATA" | grep -qi "Intel"; then
            GPU_TYPE=$(echo "$GPU_DATA" | grep "Chipset Model" | grep -i intel | head -1 | cut -d: -f2 | xargs)

            # Intel Arc GPUs
            if [[ "$GPU_TYPE" == *"Arc"* ]]; then
                case "$GPU_TYPE" in
                    *"A770"*) VRAM_GB=16 ;;
                    *"A750"*) VRAM_GB=8 ;;
                    *"A380"*) VRAM_GB=6 ;;
                    *) VRAM_GB=4 ;;
                esac
            else
                # Integrated graphics
                VRAM_GB=2
            fi
        else
            # Fallback for integrated graphics
            VRAM_GB=2
            GPU_TYPE="Integrated Graphics"
        fi
    fi

    if [ $VRAM_GB -eq 0 ]; then
        VRAM_GB=2  # Fallback for integrated graphics
        GPU_TYPE="Integrated Graphics"
    fi

    echo -e "  GPU: $GPU_TYPE"
    echo -e "  Estimated VRAM: ${VRAM_GB}GB"

    if [ "$HAS_NVIDIA_GPU" = true ]; then
        echo -e "  ${YELLOW}CUDA acceleration available${NC}"
    fi

    echo ""
}

# Function to calculate available memory for models
calculate_available_memory() {
    # Reserve memory for system and applications
    SYSTEM_RESERVE_GB=4

    if $IS_APPLE_SILICON; then
        # Unified memory - can use more flexibly
        AVAILABLE_RAM_GB=$((TOTAL_RAM_GB - SYSTEM_RESERVE_GB))
        AVAILABLE_VRAM_GB=$AVAILABLE_RAM_GB
    else
        # Separate RAM and VRAM
        AVAILABLE_RAM_GB=$((TOTAL_RAM_GB - SYSTEM_RESERVE_GB))
        AVAILABLE_VRAM_GB=$VRAM_GB
    fi

    # The limiting factor
    if [ $AVAILABLE_VRAM_GB -lt $AVAILABLE_RAM_GB ]; then
        MAX_MODEL_SIZE_GB=$AVAILABLE_VRAM_GB
    else
        MAX_MODEL_SIZE_GB=$AVAILABLE_RAM_GB
    fi

    echo -e "${GREEN}Available Resources for Models:${NC}"
    echo -e "  Usable RAM: ${AVAILABLE_RAM_GB}GB"
    echo -e "  Usable VRAM: ${AVAILABLE_VRAM_GB}GB"
    echo -e "  Max Model Size: ${MAX_MODEL_SIZE_GB}GB"
    echo ""
}

# Function to recommend models based on available resources
recommend_models() {
    echo -e "${GREEN}Recommended Models for Coding:${NC}\n"

    # Load models from CSV file
    declare -a models=()
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/models.csv" ]; then
        # Read CSV file, skip header line
        while IFS=',' read -r name min_gb rec_gb context desc; do
            # Skip header line
            if [[ "$name" != "Name" ]]; then
                models+=("$name,$min_gb,$rec_gb,$context,$desc")
            fi
        done < "$SCRIPT_DIR/models.csv"
    else
        echo -e "${RED}Error: models.csv file not found!${NC}"
        return 1
    fi

    RECOMMENDED_COUNT=0
    POSSIBLE_COUNT=0

    echo -e "${BLUE}Optimal Choices:${NC}"
    for model_info in "${models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "$model_info"

        if [ $MAX_MODEL_SIZE_GB -ge $rec_gb ]; then
            echo -e "  ${GREEN}✓${NC} $model"
            echo -e "     Memory: ${rec_gb}GB | Context: ${context} tokens"
            echo -e "     $desc"

            # Suggest optimal context window based on available RAM
            if [ $AVAILABLE_RAM_GB -ge $((rec_gb + 4)) ]; then
                echo -e "     ${YELLOW}Recommended settings:${NC}"
                echo -e "     ollama run $model"
                echo -e "     Can use full ${context} token context"
            else
                adjusted_context=$((context / 2))
                echo -e "     ${YELLOW}Recommended settings:${NC}"
                echo -e "     ollama run $model"
                echo -e "     Consider reducing context to ${adjusted_context} tokens if OOM"
            fi
            echo ""
            ((RECOMMENDED_COUNT++))
        fi
    done

    if [ $RECOMMENDED_COUNT -eq 0 ]; then
        echo -e "  ${YELLOW}No optimal models for your configuration${NC}\n"
    fi

    echo -e "${BLUE}Possible with Reduced Performance:${NC}"
    for model_info in "${models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "$model_info"

        if [ $MAX_MODEL_SIZE_GB -ge $min_gb ] && [ $MAX_MODEL_SIZE_GB -lt $rec_gb ]; then
            echo -e "  ${YELLOW}⚠${NC} $model"
            echo -e "     Minimum: ${min_gb}GB | Recommended: ${rec_gb}GB"
            echo -e "     $desc"

            # Calculate reduced context window
            reduction_factor=$(echo "scale=2; $MAX_MODEL_SIZE_GB / $rec_gb" | bc)
            adjusted_context=$(echo "scale=0; $context * $reduction_factor" | bc)
            adjusted_context=${adjusted_context%.*}  # Remove decimals

            echo -e "     ${YELLOW}Adjusted settings:${NC}"
            echo -e "     Reduce context to ~${adjusted_context} tokens"
            echo -e "     May experience slower performance"
            echo ""
            ((POSSIBLE_COUNT++))
        fi
    done

    if [ $POSSIBLE_COUNT -eq 0 ] && [ $RECOMMENDED_COUNT -eq 0 ]; then
        echo -e "  ${RED}✗${NC} Your system (${MAX_MODEL_SIZE_GB}GB available) may struggle with larger models"
        echo -e "     Consider these lightweight options:"
        echo -e "     - stable-code:3b (3GB minimum)"
        echo -e "     - codegemma:2b (2GB minimum)"
        echo ""
    fi
}

# Function to create Modelfile with optimized settings
create_optimized_modelfile() {
    local base_model=$1
    local context_size=$2
    local output_file="Modelfile.optimized"

    cat > "$output_file" << EOF
# Optimized Modelfile for $base_model
FROM $base_model

# Optimized parameters based on system resources
PARAMETER num_ctx $context_size
PARAMETER num_batch 512
PARAMETER num_gpu 999  # Use all available GPU layers
PARAMETER num_thread 8

# Temperature for coding (more deterministic)
PARAMETER temperature 0.2
PARAMETER top_p 0.95
PARAMETER top_k 40

# System prompt for coding
SYSTEM """You are an expert programming assistant. Provide clear, concise, and well-commented code. Follow best practices and explain your solutions when needed."""
EOF

    echo -e "${GREEN}Created optimized Modelfile: $output_file${NC}"
    echo -e "To use: ollama create my-optimized-model -f $output_file"
}

# Function to get installed Ollama models
get_installed_models() {
    local installed_models=()
    if ollama list &>/dev/null; then
        # Parse ollama list output, skip header line
        while IFS= read -r line; do
            if [[ -n "$line" && ! "$line" =~ ^NAME ]]; then
                model_name=$(echo "$line" | awk '{print $1}')
                if [[ -n "$model_name" ]]; then
                    installed_models+=("$model_name")
                fi
            fi
        done < <(ollama list 2>/dev/null | tail -n +2)
    fi
    printf '%s\n' "${installed_models[@]}"
}

# Function to check if aider is installed
check_aider_installation() {
    command -v aider &> /dev/null
}

# Function to install aider
install_aider() {
    echo ""
    echo -e "${YELLOW}Installing aider...${NC}"
    echo "Aider requires Python and pip to be installed."
    echo ""

    if command -v pip3 &> /dev/null; then
        echo "Installing aider-chat via pip3..."
        if pip3 install aider-chat; then
            echo -e "${GREEN}Aider installed successfully!${NC}"
            return 0
        else
            echo -e "${RED}Failed to install aider${NC}"
            return 1
        fi
    elif command -v pip &> /dev/null; then
        echo "Installing aider-chat via pip..."
        if pip install aider-chat; then
            echo -e "${GREEN}Aider installed successfully!${NC}"
            return 0
        else
            echo -e "${RED}Failed to install aider${NC}"
            return 1
        fi
    else
        echo -e "${RED}Python/pip not found. Please install Python first:${NC}"
        echo "Install from: https://www.python.org/downloads/"
        echo "Or use Homebrew: brew install python"
        return 1
    fi
}

# Function to launch aider with selected model
launch_aider_with_model() {
    local model_name=$1

    echo ""
    echo -n "Would you like to launch aider with this model? (y/n): "
    read -r aider_response

    if [[ ! "$aider_response" =~ ^[Yy]$ ]]; then
        return
    fi

    # Check if aider is installed
    if ! check_aider_installation; then
        echo -e "${YELLOW}Aider is not installed.${NC}"
        echo -n "Would you like to install aider now? (y/n): "
        read -r install_aider_response

        if [[ "$install_aider_response" =~ ^[Yy]$ ]]; then
            if ! install_aider; then
                return
            fi
        else
            echo "You can install aider later with: pip install aider-chat"
            return
        fi
    fi

    echo ""
    echo -e "${GREEN}Launching aider with $model_name...${NC}"
    echo ""
    echo "Aider will start in a moment. Press Ctrl+C to exit aider when done."
    echo ""

    # Launch aider with the selected model
    aider --model "ollama/$model_name"
}

# Function to install and pull recommended model with menu
install_recommended_model() {
    echo ""
    echo -e "${BLUE}Model Installation:${NC}"

    # Check for already installed models
    installed_models=()
    while IFS= read -r line; do
        installed_models+=("$line")
    done < <(get_installed_models)
    installed_recommended=()

    # Load models from CSV file or use fallback
    declare -a recommended_models=()
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ -f "$SCRIPT_DIR/models.csv" ]; then
        echo -e "${GREEN}Loading models from models.csv...${NC}"
        # Read CSV file, skip header line
        while IFS=',' read -r name min_gb rec_gb context desc; do
            # Skip header line and empty lines
            if [[ "$name" != "name" && -n "$name" ]]; then
                recommended_models+=("$name,$min_gb,$rec_gb,$context,$desc")
            fi
        done < "$SCRIPT_DIR/models.csv"
    elif [ -f "$SCRIPT_DIR/fallback_models.csv" ]; then
        # Fallback to fallback model list
        echo -e "${YELLOW}Loading fallback models (run ./refresh-models.sh to get latest)${NC}"
        while IFS=',' read -r name min_gb rec_gb context desc; do
            # Skip header line and empty lines
            if [[ "$name" != "name" && -n "$name" ]]; then
                recommended_models+=("$name,$min_gb,$rec_gb,$context,$desc")
            fi
        done < "$SCRIPT_DIR/fallback_models.csv"
    else
        echo -e "${RED}Error: No model files found (models.csv or fallback_models.csv)${NC}"
        echo "Run ./refresh-models.sh to generate models.csv"
        return 1
    fi
    echo ""

    declare -a possible_models=()

    # Categorize models based on available memory
    for model_info in "${recommended_models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "$model_info"
        if [[ " ${installed_models[*]} " =~ " ${model} " ]]; then
            installed_recommended+=("$model_info")
        fi

        if [ $MAX_MODEL_SIZE_GB -ge $rec_gb ]; then
            # This is an optimal model (not necessarily installed)
            continue
        elif [ $MAX_MODEL_SIZE_GB -ge $min_gb ]; then
            possible_models+=("$model_info")
        fi
    done

    # Show already installed models if any
    if [ ${#installed_recommended[@]} -gt 0 ]; then
        echo -e "${GREEN}Already installed optimal models:${NC}"
        for i in "${!installed_recommended[@]}"; do
            IFS=',' read -r model min_gb rec_gb context desc <<< "${installed_recommended[i]}"
            echo -e "  [$((i + 1))] $model - ${rec_gb}GB"
        done
        echo ""

        echo -n "Use an already installed model? (y/n): "
        read -r use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            if [ ${#installed_recommended[@]} -eq 1 ]; then
                IFS=',' read -r selected_model min_gb rec_gb context desc <<< "${installed_recommended[0]}"
            else
                echo -n "Select model number (1-${#installed_recommended[@]}): "
                read -r selection
                index=$((selection - 1))
                if [ $index -ge 0 ] && [ $index -lt ${#installed_recommended[@]} ]; then
                    IFS=',' read -r selected_model min_gb rec_gb context desc <<< "${installed_recommended[index]}"
                else
                    echo -e "${RED}Invalid selection${NC}"
                    return
                fi
            fi

            echo ""
            echo -e "${GREEN}Selected: $selected_model${NC}"
            launch_aider_with_model "$selected_model"
            return
        fi
    fi

    # Offer to install a new model
    echo -n "Would you like to install a new model? (y/n): "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        return
    fi

    # Combine optimal and possible models for menu
    declare -a all_models=()
    for model_info in "${recommended_models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "$model_info"
        if [ $MAX_MODEL_SIZE_GB -ge $rec_gb ]; then
            all_models+=("$model_info")
        fi
    done

    # Add possible models
    for model_info in "${possible_models[@]}"; do
        all_models+=("$model_info")
    done

    if [ ${#all_models[@]} -eq 0 ]; then
        echo -e "${RED}No models available for your system configuration${NC}"
        return
    fi

    # Display menu
    echo ""
    echo -e "${BLUE}Select a model to install:${NC}"
    echo ""

    optimal_count=0
    for model_info in "${recommended_models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "$model_info"
        if [ $MAX_MODEL_SIZE_GB -ge $rec_gb ]; then
            ((optimal_count++))
        fi
    done

    for i in "${!all_models[@]}"; do
        IFS=',' read -r model min_gb rec_gb context desc <<< "${all_models[i]}"
        if [ $i -lt $optimal_count ]; then
            echo -e "  [$((i + 1))] ${GREEN}[OPTIMAL]${NC} $model"
        else
            echo -e "  [$((i + 1))] ${YELLOW}[REDUCED]${NC} $model"
        fi
        echo -e "      Memory: ${rec_gb}GB | Context: ${context} tokens"
    done

    echo ""
    echo -e "  [0] Enter custom model name"
    echo ""

    echo -n "Select model number (0-${#all_models[@]}): "
    read -r selection

    model_name=""
    selected_model_info=""

    if [ "$selection" -eq 0 ]; then
        echo -n "Enter custom model name (e.g., qwen2.5-coder:7b-instruct-q5_K_M): "
        read -r model_name
    else
        index=$((selection - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#all_models[@]} ]; then
            selected_model_info="${all_models[index]}"
            IFS=',' read -r model_name min_gb rec_gb context desc <<< "$selected_model_info"
        else
            echo -e "${RED}Invalid selection${NC}"
            return
        fi
    fi

    if [ -z "$model_name" ]; then
        echo -e "${RED}No model selected${NC}"
        return
    fi

    # Pull the model
    echo ""
    echo -e "${YELLOW}Pulling $model_name...${NC}"
    echo "This may take several minutes depending on model size and connection speed..."
    echo ""

    if ollama pull "$model_name"; then
        echo ""
        echo -e "${GREEN}Model installed successfully!${NC}"
        echo -e "Run with: ${BLUE}ollama run $model_name${NC}"

        # Offer to create optimized Modelfile
        echo ""
        echo -n "Create an optimized Modelfile? (y/n): "
        read -r optimize_response

        if [[ "$optimize_response" =~ ^[Yy]$ ]]; then
            if [[ -n "$selected_model_info" ]]; then
                IFS=',' read -r model min_gb rec_gb context desc <<< "$selected_model_info"
                create_optimized_modelfile "$model_name" "$context"
            else
                echo -n "Enter context size (e.g., 16384): "
                read -r context_size
                create_optimized_modelfile "$model_name" "$context_size"
            fi
        fi

        # Offer to launch aider
        launch_aider_with_model "$model_name"
    else
        echo -e "${RED}Failed to install model${NC}"
    fi
}

# Function to check if Ollama is installed
check_ollama_installation() {
    if ! command -v ollama &> /dev/null; then
        echo -e "${RED}Ollama is not installed or not in PATH!${NC}"
        echo "Install it from: https://ollama.ai/download"
        echo ""
        echo "After installation, make sure Ollama is in your PATH:"
        echo "1. Add Ollama installation directory to PATH environment variable"
        echo "2. Restart your terminal"
        return 1
    fi
    return 0
}

# Function to check if Ollama service is running
check_ollama_service() {
    if ! ollama list &>/dev/null; then
        echo -e "${YELLOW}Starting Ollama service...${NC}"
        # Start ollama serve in background
        nohup ollama serve > /dev/null 2>&1 &
        sleep 3

        # Verify it's working
        if ! ollama list &>/dev/null; then
            echo -e "${RED}Failed to start Ollama service${NC}"
            return 1
        fi
    fi
    return 0
}

# Function to display optimization tips
show_optimization_tips() {
    echo ""
    echo -e "${GREEN}Optimization complete!${NC}"
    echo -e "${BLUE}Tips for best performance:${NC}"
    echo -e "  • Close unnecessary applications to free up RAM"
    echo -e "  • Use quantized models (q4_K_M, q5_K_M) for better memory efficiency"
    echo -e "  • Adjust context window size if you experience out-of-memory errors"
    echo -e "  • For coding, models with 'coder' or 'code' in the name perform best"

    if [ "$HAS_NVIDIA_GPU" = true ]; then
        echo -e "  • Your NVIDIA GPU will use CUDA acceleration for better performance"
        echo -e "  • Ensure you have the latest NVIDIA drivers installed"
    fi

    if [ "$HAS_AMD_GPU" = true ]; then
        echo -e "  • Your AMD GPU can use Metal acceleration on macOS"
        echo -e "  • Ensure you have the latest AMD drivers installed"
    fi

    if [ "$IS_APPLE_SILICON" = true ]; then
        echo -e "  • Your Apple Silicon Mac uses unified memory efficiently"
        echo -e "  • Metal acceleration is automatically enabled for better performance"
    fi

    echo ""
    echo -e "${BLUE}Advanced Configuration:${NC}"
    echo -e "  Set environment variables for fine-tuning:"
    echo -e "  • OLLAMA_NUM_GPU=999 (use all GPU layers)"
    echo -e "  • OLLAMA_MAX_LOADED_MODELS=1 (reduce memory usage)"
    echo -e "  • OLLAMA_KEEP_ALIVE=5m (keep model in memory for 5 minutes)"
    echo ""
    echo -e "  To set permanently in your shell profile (~/.zshrc or ~/.bash_profile):"
    echo -e "  export OLLAMA_NUM_GPU=999"
    echo -e "  export OLLAMA_MAX_LOADED_MODELS=1"
    echo -e "  export OLLAMA_KEEP_ALIVE=5m"
    echo ""
    echo -e "  Or set for current session:"
    echo -e "  export OLLAMA_NUM_GPU=999"
}

# Main execution function
start_ollama_optimizer() {
    # Check for sudo access (optional but helpful for system info)
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Note: Running as root may provide more accurate system information${NC}"
        echo ""
    fi

    # Check if Ollama is installed
    if ! check_ollama_installation; then
        return 1
    fi

    # Check if Ollama service is running
    if ! check_ollama_service; then
        return 1
    fi

    # Get system information
    get_system_info

    # Calculate available memory
    calculate_available_memory

    # Get model recommendations
    recommend_models

    # Offer to install a model
    install_recommended_model

    # Show optimization tips
    show_optimization_tips
}

# Error handling wrapper
if ! start_ollama_optimizer; then
    echo -e "${RED}An error occurred during optimization${NC}"
    exit 1
fi
