# Ollama Model Optimizer

Intelligent scripts that automatically detect your system's hardware capabilities and recommend optimal Ollama models for local AI-powered coding assistance.

## 🎯 Purpose

Running large language models locally requires careful balancing of model capabilities with available system resources. These scripts eliminate the guesswork by:

- Automatically detecting your RAM, VRAM, and GPU capabilities
- Recommending the best coding models that will run smoothly on your hardware
- Configuring optimal quantization and context window settings
- Preventing out-of-memory crashes through intelligent resource management

## 🚀 Quick Start

### macOS

```bash
# Download the script
curl -O https://raw.githubusercontent.com/yourusername/ollama-optimizer/main/ollama_optimizer.sh

# Make it executable
chmod +x ollama_optimizer.sh

# Run the optimizer
./ollama_optimizer.sh
```

### Windows

```powershell
# Download the script (or save it manually as ollama_optimizer.ps1)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yourusername/ollama-optimizer/main/ollama_optimizer.ps1" -OutFile "ollama_optimizer.ps1"

# Enable PowerShell script execution (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the optimizer
.\ollama_optimizer.ps1
```

## 📋 Prerequisites

### Required
- **Ollama**: Download from [ollama.ai](https://ollama.ai/download)
- **Operating System**: 
  - macOS 11.0+ (Intel or Apple Silicon)
  - Windows 10/11 with PowerShell 5.0+

### Recommended
- **RAM**: Minimum 8GB (16GB+ recommended)
- **GPU**: 
  - NVIDIA GPU with CUDA support (4GB+ VRAM)
  - AMD GPU with ROCm support
  - Apple Silicon (M1/M2/M3) with unified memory
  - Intel Arc graphics

## 💻 What the Scripts Do

### 1. System Detection
```
System Information:
  CPU: Apple M2 Pro
  Total RAM: 32GB
  GPU: Apple Silicon (Unified Memory)
  Available VRAM: 32GB
```

### 2. Resource Calculation
- Reserves 4GB RAM for system stability
- Calculates maximum safe model size
- Determines optimal GPU layer allocation

### 3. Model Recommendations

**Optimal Choices** (full performance):
```
✓ qwen2.5-coder:7b-instruct-q5_K_M
  Memory: 6GB | Context: 32768 tokens
  Efficient 7B model with Q5 quantization
  Can use full 32768 token context
```

**Possible with Adjustments** (reduced performance):
```
⚠ qwen2.5-coder:14b-instruct-q5_K_M
  Minimum: 12GB | Recommended: 16GB
  Reduce context to ~16384 tokens
  May experience slower performance
```

### 4. Guided Installation
- Interactive model selection
- Automatic download via `ollama pull`
- Custom Modelfile generation with optimized settings

## 🎮 Understanding Model Recommendations

### Model Naming Convention
```
model-name:size-variant-quantization
```
- **model-name**: Base model (e.g., qwen2.5-coder, codellama)
- **size**: Parameter count (e.g., 7b = 7 billion parameters)
- **variant**: Model type (e.g., instruct, base)
- **quantization**: Compression level (e.g., q4_K_M, q5_K_M, q8_0)

### Quantization Levels
| Level | Quality | Size | Speed | Use Case |
|-------|---------|------|-------|----------|
| q8_0 | Highest | Large | Slower | Best quality when RAM allows |
| q5_K_M | Good | Medium | Balanced | Best compromise |
| q4_K_M | Fair | Small | Faster | Larger models on limited hardware |

### Context Window
- **32768 tokens**: Full documentation, large codebases
- **16384 tokens**: Standard coding tasks
- **8192 tokens**: Quick edits, small functions
- **4096 tokens**: Minimum for basic assistance

## 📊 Hardware Requirements by Model Tier

### Minimum Specifications
| Model Class | RAM | VRAM | Example Hardware |
|------------|-----|------|------------------|
| 3B Models | 8GB | 4GB | GTX 1650, M1 MacBook Air |
| 7B Models | 16GB | 6GB | RTX 3060, M2 MacBook Pro |
| 13B Models | 24GB | 12GB | RTX 3080, M2 Pro |
| 34B Models | 32GB | 24GB | RTX 4090, M2 Max |

### Recommended Models by Use Case

**Quick Code Completion** (3-7B models):
- `stable-code:3b-q8_0` - Fastest responses
- `codegemma:7b-instruct-q5_K_M` - Good balance

**Full-Stack Development** (7-14B models):
- `qwen2.5-coder:7b-instruct-q5_K_M` - Best overall
- `codellama:13b-instruct-q5_K_M` - Strong reasoning

**Complex Architecture** (14B+ models):
- `qwen2.5-coder:14b-instruct-q5_K_M` - Excellent understanding
- `deepseek-coder-v2:16b-lite-instruct-q4_K_M` - Deep analysis

## 🛠️ Advanced Configuration

### Environment Variables

Set these before running Ollama for fine-tuning:

```bash
# macOS/Linux
export OLLAMA_NUM_GPU=999          # Use all GPU layers
export OLLAMA_MAX_LOADED_MODELS=1  # Only keep one model in memory
export OLLAMA_KEEP_ALIVE=5m        # Keep model loaded for 5 minutes

# Windows PowerShell
[Environment]::SetEnvironmentVariable("OLLAMA_NUM_GPU", "999", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_MAX_LOADED_MODELS", "1", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "5m", "User")
```

### Custom Modelfile Example

The scripts generate optimized Modelfiles like this:

```dockerfile
FROM qwen2.5-coder:7b-instruct-q5_K_M

# Optimized parameters
PARAMETER num_ctx 16384      # Context window size
PARAMETER num_batch 512      # Batch size for prompt processing
PARAMETER num_gpu 999        # GPU layers (999 = all)
PARAMETER num_thread 8       # CPU threads

# Temperature for coding (more deterministic)
PARAMETER temperature 0.2
PARAMETER top_p 0.95
PARAMETER top_k 40

SYSTEM """You are an expert programming assistant. Provide clear, 
concise, and well-commented code. Follow best practices and explain 
your solutions when needed."""
```

### Creating Custom Models

```bash
# Create from Modelfile
ollama create my-coding-assistant -f Modelfile.optimized

# Run your custom model
ollama run my-coding-assistant
```

## 🔧 Troubleshooting

### Out of Memory Errors

1. **Reduce context window**:
   ```bash
   ollama run model --num-ctx 8192
   ```

2. **Use more aggressive quantization**:
   - Switch from q5_K_M to q4_K_M
   - Switch from q8_0 to q5_K_M

3. **Close other applications** to free RAM

### Slow Performance

1. **Check GPU usage**:
   ```bash
   # NVIDIA
   nvidia-smi
   
   # macOS
   sudo powermetrics --samplers gpu_power
   ```

2. **Ensure GPU acceleration**:
   ```bash
   ollama run model --verbose
   # Look for "loaded X GPU layers"
   ```

3. **Reduce model size** or use lighter quantization

### Model Not Found

```bash
# List available models
ollama list

# Search for models
ollama search coder

# Pull specific model
ollama pull qwen2.5-coder:7b-instruct-q5_K_M
```

## 📈 Performance Optimization Tips

### Memory Management
- **Close browsers** - Can free 2-4GB RAM
- **Disable startup programs** - Reduces background memory usage
- **Use single model** - Set `OLLAMA_MAX_LOADED_MODELS=1`

### Speed Optimization
- **SSD storage** - Place models on fast drives
- **GPU drivers** - Keep CUDA/ROCm drivers updated
- **Power mode** - Set system to high performance

### Quality vs Speed Trade-offs
- **Higher quality**: Use q8_0 quantization, larger context
- **Faster responses**: Use q4_K_M, reduce context to 4096
- **Balanced**: q5_K_M with 8192-16384 context

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional model recommendations
- Better VRAM detection methods
- Support for more GPUs
- Linux version of the script
- Docker containerization

## 📄 License

MIT License - Feel free to modify and distribute

## 🔗 Resources

- [Ollama Documentation](https://github.com/ollama/ollama)
- [Model Library](https://ollama.ai/library)
- [Quantization Guide](https://github.com/ggerganov/llama.cpp/wiki/Quantization)
- [CUDA Installation](https://developer.nvidia.com/cuda-downloads)
- [ROCm Installation](https://rocm.docs.amd.com/en/latest/)

## 💬 Support

For issues or questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review Ollama's [official documentation](https://github.com/ollama/ollama)
3. Open an issue on GitHub

---

**Note**: Model recommendations and performance will vary based on specific hardware configurations, driver versions, and system load. The scripts provide conservative estimates to ensure stability.