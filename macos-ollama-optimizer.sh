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
    # Get total RAM in GB
    TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
    TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1073741824))
    
    # Check for Apple Silicon
    CHIP_TYPE=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    
    # Check for GPU (Metal Performance Shaders)
    if [[ "$CHIP_TYPE" == *"Apple"* ]]; then
        # Apple Silicon unified memory
        VRAM_GB=$TOTAL_RAM_GB
        GPU_TYPE="Apple Silicon (Unified Memory)"
        IS_APPLE_SILICON=true
    else
        # Intel Mac - check for discrete GPU
        GPU_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 || echo "")
        if [[ -n "$GPU_INFO" ]]; then
            GPU_TYPE=$(echo "$GPU_INFO" | cut -d: -f2 | xargs)
            # Estimate VRAM (rough approximation for Intel Macs)
            if [[ "$GPU_INFO" == *"AMD"* ]] || [[ "$GPU_INFO" == *"Radeon"* ]]; then
                VRAM_GB=8  # Typical for discrete AMD GPUs
            elif [[ "$GPU_INFO" == *"NVIDIA"* ]]; then
                VRAM_GB=8  # Typical for discrete NVIDIA GPUs
            else
                VRAM_GB=2  # Integrated graphics
            fi
        else
            VRAM_GB=2
            GPU_TYPE="Integrated Graphics"
        fi
        IS_APPLE_SILICON=false
    fi
    
    echo -e "${GREEN}System Information:${NC}"
    echo -e "  CPU: $CHIP_TYPE"
    echo -e "  Total RAM: ${TOTAL_RAM_GB}GB"
    echo -e "  GPU: $GPU_TYPE"
    echo -e "  Available VRAM: ${VRAM_GB}GB"
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
    
    # Model configurations: name, min_gb, recommended_gb, context, description
    declare -a models=(
        "qwen2.5-coder:32b-instruct-q4_K_M,20,24,32768,Excellent 32B coding model with Q4 quantization"
        "qwen2.5-coder:14b-instruct-q5_K_M,12,16,32768,Great 14B coding model with Q5 quantization"
        "qwen2.5-coder:7b-instruct-q8_0,8,10,32768,Solid 7B model with high quality Q8 quantization"
        "qwen2.5-coder:7b-instruct-q5_K_M,5,6,32768,Efficient 7B model with Q5 quantization"
        "deepseek-coder-v2:16b-lite-instruct-q4_K_M,10,12,16384,DeepSeek 16B lightweight version"
        "codellama:34b-instruct-q4_K_M,20,24,16384,Meta's 34B CodeLlama with Q4 quantization"
        "codellama:13b-instruct-q5_K_M,10,12,16384,Meta's 13B CodeLlama with Q5 quantization"
        "codellama:7b-instruct-q8_0,8,10,16384,Meta's 7B CodeLlama with high quality"
        "starcoder2:15b-q4_K_M,10,12,16384,StarCoder2 15B for code completion"
        "starcoder2:7b-q5_K_M,5,6,16384,StarCoder2 7B efficient version"
        "codegemma:7b-instruct-q5_K_M,5,6,8192,Google's CodeGemma 7B"
        "granite-code:8b-instruct-q4_K_M,5,6,8192,IBM Granite Code 8B"
        "stable-code:3b-q8_0,3,4,16384,Stability AI's compact 3B model"
    )
    
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

# Function to install and pull recommended model
install_model() {
    echo -e "\n${BLUE}Model Installation:${NC}"
    echo -e "Would you like to install a recommended model? (y/n): \c"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "Enter the model name (e.g., qwen2.5-coder:7b-instruct-q5_K_M): \c"
        read -r model_name
        
        echo -e "\n${YELLOW}Pulling $model_name...${NC}"
        ollama pull "$model_name"
        
        echo -e "\n${GREEN}Model installed successfully!${NC}"
        echo -e "Run with: ${BLUE}ollama run $model_name${NC}"
        
        # Offer to create optimized Modelfile
        echo -e "\nCreate an optimized Modelfile? (y/n): \c"
        read -r optimize_response
        
        if [[ "$optimize_response" =~ ^[Yy]$ ]]; then
            echo -e "Enter context size (e.g., 16384): \c"
            read -r context_size
            create_optimized_modelfile "$model_name" "$context_size"
        fi
    fi
}

# Function to check if Ollama is installed
check_ollama() {
    if ! command -v ollama &> /dev/null; then
        echo -e "${RED}Ollama is not installed!${NC}"
        echo -e "Install it from: https://ollama.ai/download"
        exit 1
    fi
    
    # Check if Ollama service is running
    if ! ollama list &> /dev/null; then
        echo -e "${YELLOW}Starting Ollama service...${NC}"
        ollama serve &
        sleep 3
    fi
}

# Main execution
main() {
    check_ollama
    get_system_info
    calculate_available_memory
    recommend_models
    install_model
    
    echo -e "\n${GREEN}Optimization complete!${NC}"
    echo -e "${BLUE}Tips for best performance:${NC}"
    echo -e "  • Close unnecessary applications to free up RAM"
    echo -e "  • Use quantized models (q4_K_M, q5_K_M) for better memory efficiency"
    echo -e "  • Adjust context window size if you experience out-of-memory errors"
    echo -e "  • For coding, models with 'coder' or 'code' in the name perform best"
    
    if $IS_APPLE_SILICON; then
        echo -e "  • Your Apple Silicon Mac uses unified memory efficiently"
        echo -e "  • Metal acceleration is automatically enabled for better performance"
    fi
}

# Run the script
main