# Isaac ROS without Docker on x86 Compute Platforms

## Requirements

| Requirement | Value |
|---|---|
| GPU | NVIDIA (Ampere or higher recommended) |
| CUDA Version | 12.6+ |
| Ubuntu | 22.04+ |
| RAM | 8 GB+ |
| VRAM | 6+ GB |

## Getting Started

The Isaac ROS suite has been developed and released by NVIDIA to leverage the power of NVIDIA acceleration on NVIDIA Jetson and discrete GPUs for standard robotics applications.

Isaac ROS uses standard ROS interfaces on input and output topics, making it extremely easy to use as a drop-in replacement for commonly-used, CPU-based ROS implementations familiar to robotics developers.

### System Requirements

| Platform | Hardware | Software | Notes |
|---|---|---|---|
| Jetson | Jetson Orin | JetPack 6.0 | For best performance, ensure that power settings are configured appropriately. Jetson Orin Nano 4GB may not have enough memory to run many of the Isaac ROS packages and is not recommended. |
| x86_64 | Ampere or higher NVIDIA GPU Architecture with 8 GB RAM or higher | Ubuntu 22.04+ | CUDA 12.2+ |

## Compute Setup

### x86 Platforms

1. Prepare a NVIDIA-powered platform with the following minimum specs:
   - Ubuntu 22.04+
     - **Experimental**: WSL2 on Windows 11
   - 16 GB general RAM
   - Discrete NVIDIA GPU with the following specs:
     - Supports CUDA 12.2+ with Volta or newer
     - Minimum 8GB of VRAM (recommended 12GB+)


