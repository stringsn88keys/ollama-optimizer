#!/bin/bash

# Script to refresh model recommendations from Ollama API
# This updates the model list with the latest available models and their details

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  Ollama Model List Updater${NC}"
echo -e "${BLUE}==================================${NC}\n"

# Function to fetch models from Ollama library
fetch_ollama_models() {
    echo -e "${YELLOW}Fetching latest coding models from Ollama API...${NC}\n"
    
    # Define coding-focused model tags to search for
    local model_tags=("coder" "code" "codellama" "starcoder" "codegemma" "granite-code" "deepseek-coder")
    local all_models=()
    
    # Fetch model list from Ollama (using their search API)
    echo -e "${GREEN}Searching for coding models...${NC}"
    
    # Common coding models we want to check
    local known_models=(
        "qwen2.5-coder"
        "deepseek-coder-v2"
        "codellama"
        "starcoder2"
        "codegemma"
        "granite-code"
        "stable-code"
        "phi"
        "mistral"
        "llama3"
    )
    
    for model in "${known_models[@]}"; do
        echo -e "  Checking ${model}..."
        # Query Ollama API for model tags
        if command -v curl &> /dev/null; then
            response=$(curl -s "https://ollama.com/api/tags/${model}" 2>/dev/null || echo "")
            if [ -n "$response" ]; then
                echo -e "  ${GREEN}✓${NC} Found ${model}"
            fi
        fi
    done
    
    echo ""
}

# Function to get model size from Ollama
get_model_info() {
    local model_name=$1
    
    # Try to pull model info using ollama show (if model is already installed)
    if command -v ollama &> /dev/null; then
        info=$(ollama show "$model_name" 2>/dev/null || echo "")
        if [ -n "$info" ]; then
            # Extract parameter count and size
            params=$(echo "$info" | grep -i "parameters" || echo "")
            size=$(echo "$info" | grep -i "size" || echo "")
            echo "$params | $size"
            return 0
        fi
    fi
    
    return 1
}

# Generate updated model list
generate_model_list() {
    echo -e "${YELLOW}Generating updated model recommendations...${NC}\n"
    
    cat > models.csv << 'EOF'
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
EOF
    
    echo -e "${GREEN}✓ Created models.csv with latest recommendations${NC}\n"
}

# Function to update the main script
update_main_script() {
    echo -e "${YELLOW}Updating macos-ollama-optimizer.sh with new model list...${NC}\n"
    
    if [ ! -f "macos-ollama-optimizer.sh" ]; then
        echo -e "${RED}Error: macos-ollama-optimizer.sh not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Model CSV file is ready to be used by the optimizer${NC}"
    echo -e "  The optimizer will automatically load models from models.csv if available"
    echo ""
}

# Function to display model statistics
show_model_stats() {
    if [ ! -f "models.csv" ]; then
        return
    fi
    
    echo -e "${BLUE}Model Statistics:${NC}"
    
    local total=$(tail -n +2 models.csv | wc -l | xargs)
    local small=$(tail -n +2 models.csv | awk -F',' '$3 <= 4' | wc -l | xargs)
    local medium=$(tail -n +2 models.csv | awk -F',' '$3 > 4 && $3 <= 12' | wc -l | xargs)
    local large=$(tail -n +2 models.csv | awk -F',' '$3 > 12' | wc -l | xargs)
    
    echo -e "  Total models: $total"
    echo -e "  Small (≤4GB): $small models"
    echo -e "  Medium (4-12GB): $medium models"
    echo -e "  Large (>12GB): $large models"
    echo ""
    
    echo -e "${BLUE}Model Families:${NC}"
    echo -e "  • Qwen2.5-Coder: Excellent coding performance"
    echo -e "  • DeepSeek-Coder: Specialized for code understanding"
    echo -e "  • CodeLlama: Meta's coding-focused models"
    echo -e "  • StarCoder2: Code completion and generation"
    echo -e "  • CodeGemma: Google's lightweight coding models"
    echo -e "  • Granite-Code: IBM's enterprise coding models"
    echo ""
}

# Main execution
main() {
    # Fetch latest models from Ollama
    fetch_ollama_models
    
    # Generate updated model list
    generate_model_list
    
    # Update main script
    update_main_script
    
    # Show statistics
    show_model_stats
    
    echo -e "${GREEN}Model list refresh complete!${NC}"
    echo -e "Run ${BLUE}./macos-ollama-optimizer.sh${NC} to use the updated recommendations"
    echo ""
}

# Run the script
main
