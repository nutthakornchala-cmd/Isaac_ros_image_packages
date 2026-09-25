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

## Create a ROS 2 Workspace

For experimenting with Isaac ROS (x86_64 and Jetson without SSD):

```bash
mkdir -p ~/workspaces/isaac_ros-dev/src
echo "export ISAAC_ROS_WS=${HOME}/workspaces/isaac_ros-dev/" >> ~/.bashrc
source ~/.bashrc
```

We expect to use the `ISAAC_ROS_WS` environmental variable to refer to this ROS 2 workspace directory in the future.

Check the variable:

```bash
echo $ISAAC_ROS_WS
# /home/${user}/workspaces/isaac_ros-dev/
```

## Set Locale

```bash
locale  # check for UTF-8

sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

locale  # verify settings
```

## Install Dependencies

```bash
sudo apt update && sudo apt install gnupg wget
sudo apt install software-properties-common
sudo add-apt-repository universe
```

## Setup Source

Register the GPG key with `apt`. Two options exist — `.com` (US CDN) and `.cn` (China CDN) — choose whichever you prefer. Add the repository to your `apt` sources.

### US CDN

```bash
wget -qO - https://isaac.download.nvidia.com/isaac-ros/repos.key | sudo apt-key add -

grep -qxF "deb https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) legacy-release-3.1" /etc/apt/sources.list || \
echo "deb https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) legacy-release-3.1" | sudo tee -a /etc/apt/sources.list

sudo apt-get update
```

> **Warning:** You should not do this if you already have ROS 2 packages installed.

Next, for all other ROS 2 packages, ensure you have the official ROS apt repository sourced. This should allow for normal installation of all ROS 2 packages.

## Install Core ROS 2 Packages

```bash
sudo apt update && sudo apt install curl -y
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt update
```

**Desktop Install (Recommended):** ROS, RViz, demos, tutorials.

```bash
sudo apt install ros-humble-desktop
# and/or
sudo apt install ros-humble-desktop-full
```

**ROS-Base Install (Bare Bones):** Communication libraries, message packages, command line tools. No GUI tools.

```bash
sudo apt install ros-humble-ros-base
```

**Development tools:** Compilers and other tools to build ROS packages.

```bash
sudo apt install ros-dev-tools
```

## Clone Packages

Clone `isaac_ros_common`, `isaac_ros_nitros`, `isaac_ros_image_pipeline`, `realsense`, and `isaac_ros_apriltag`:

```bash
cd ~/workspaces/isaac_ros-dev/src

git clone -b release-3.1 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
git clone -b release-3.1 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nitros.git
git clone -b release-3.1 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_image_pipeline.git
git clone https://github.com/IntelRealSense/realsense-ros.git -b ros2-master
git clone -b release-3.1 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_apriltag.git
git clone https://github.com/osrf/negotiated.git
```

## rosdep install — ⚠️ Issue Point #2

### Symptom

```
ERROR: ... could not have their rosdep keys resolved to system dependencies:
isaac_ros_pynitros: Cannot locate rosdep definition for [posix_ipc]
isaac_ros_nitros_topic_tools: Cannot locate rosdep definition for [negotiated]
isaac_ros_nitros: Cannot locate rosdep definition for [negotiated]
(and packages that depend on negotiated)
```

**Cause:** `negotiated` (the ROS 2 package NITROS uses to negotiate message format) and `posix_ipc` (a Python library) are not in rosdep's database — this is not actually an installation problem.

### Fix

```bash
# 1. Clone the source of "negotiated" into the workspace (not distributed as apt/deb)
cd ~/workspaces/isaac_ros-dev/src
git clone https://github.com/osrf/negotiated.git

# 2. Install posix_ipc via pip (no rosdep key needed)
pip3 install posix_ipc

# 3. Re-run rosdep
cd ~/workspaces/isaac_ros-dev
rosdep install --from-paths src --ignore-src -r -y
```

**Final result:** An error about `Cannot locate rosdep definition for [posix_ipc]` may still remain even after `pip install` succeeds — **this is normal and not a problem**, because rosdep only checks "does it recognize this name in its database," not whether it's actually installed. Once `pip install` succeeds (`Successfully installed posix_ipc-1.3.2`), consider the dependency satisfied and ignore this error — confirmed by the final line:

```
#All required rosdeps installed successfully
```

## Build All Packages

```bash
cd ~/workspaces/isaac_ros-dev
colcon build --symlink-install --cmake-args -DCMAKE_CUDA_ARCHITECTURES=86 --parallel-workers 1
```

### Error 1: `Failed <<< isaac_ros_common`

`isaac_ros_common` is the first package to build and encounters the most CUDA/VPI-related problems, since it's where CMake starts `find_package` to locate the whole toolchain.

#### Error 2.1: CMake can't find the CUDA Toolkit

```
CMake Error at /usr/share/cmake-3.22/Modules/FindCUDA.cmake:859 (message):
  Specify CUDA_TOOLKIT_ROOT_DIR
```

**Cause:** CUDA 13 is installed (`nvcc --version` works), but the environment variable CMake needs has not been set.

**Fix:**

```bash
echo 'export CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda' >> ~/.bashrc
echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc
source ~/.bashrc
```

#### Error 2.2: Can't find the `vpi` package

```
CMake Error at CMakeLists.txt:31 (find_package):
  Could not find a package configuration file provided by "vpi"
```

**Cause:** VPI (Vision Programming Interface) has not been installed at all — it isn't distributed via Ubuntu's standard apt repos, so NVIDIA's own repo needs to be added.

**Fix (3 steps):**

1. Add the GPG key + repo (required before `apt update`, otherwise you get a `NO_PUBKEY` error):

```bash
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0D296FFB880FB004
sudo add-apt-repository 'deb https://repo.download.nvidia.com/jetson/x86_64/jammy r36.4 main'
sudo apt update
```

2. Check the actual package name (don't guess the VPI version — 2/3/4):

```bash
apt-cache search vpi
```

3. Install and configure the path so CMake can find it:

```bash
sudo apt install libnvvpi3 vpi3-dev
echo 'export CMAKE_PREFIX_PATH=/opt/nvidia/vpi3:${CMAKE_PREFIX_PATH}' >> ~/.bashrc
source ~/.bashrc
```

> **Note:** The repo is named "jetson," but it also has builds for x86_64 (note the `jetson/x86_64/...` URL) — you don't actually need a Jetson board.

### Error 2: `Failed <<< isaac_ros_nitros`

**Topic 3:** `isaac_ros_nitros` / `gxf_isaac_*` (NITROS core group)

Problems encountered while building NITROS itself and its various GXF extensions are related — mostly CUDA 13 issues with code written for older CUDA versions.

#### Error 3.1: `cuda/std/complex: No such file or directory`

```
fatal error: cuda/std/complex: No such file or directory
    23 | #include <cuda/std/complex> //NOLINT
```

**Cause:** CUDA 13 moved libcu++ (CCCL) into a `cccl/` subfolder instead of directly under `include/` as in older CUDA versions, so the compiler can't find the header at the standard path.

**Fix:**

```bash
echo 'export CPLUS_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl:${CPLUS_INCLUDE_PATH}' >> ~/.bashrc
echo 'export C_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl:${C_INCLUDE_PATH}' >> ~/.bashrc
source ~/.bashrc
```

#### Error 3.2: `Unsupported gpu architecture 'compute_70'` (found in `gxf_isaac_utils`)

```
nvcc fatal: Unsupported gpu architecture 'compute_70'
```

**Cause:** The code is hardcoded to compile for Volta (`compute_70`), but CUDA 13 no longer supports that old an architecture — unrelated to the actual GPU present (RTX 3050 = Ampere, sm_86).

**Fix:** Force the correct architecture to match the actual GPU on every build:

```bash
colcon build --symlink-install --cmake-args -DCMAKE_CUDA_ARCHITECTURES=86
```

#### Error 3.3: `cannot find -lnvToolsExt` (found when linking `isaac_ros_nitros`)

```
/usr/bin/ld: cannot find -lnvToolsExt: No such file or directory
```

**Cause:** CUDA 12+ changed NVTX from v2 (had a `.so` file) to v3 (header-only), so there's no `libnvToolsExt.so` to link against as before.

**Fix:**

```bash
sudo apt install libnvtoolsext1
# Only the versioned file (libnvToolsExt.so.1) exists; create a symlink so the linker can find it
sudo ln -s /usr/lib/x86_64-linux-gnu/libnvToolsExt.so.1 /usr/lib/x86_64-linux-gnu/libnvToolsExt.so
sudo ldconfig
```

> **Note:** You need `libnvtoolsext1` from the Ubuntu repo, not `cuda-nvtx-13-0` from NVIDIA (the latter is v3-only, with no `.so` file).

#### Error 3.4: `undefined reference to cudaFree@libcudart.so.12` (found in `gxf_isaac_messages`, `isaac_ros_nitros`)

```
libcudart.so.12, needed by .../libgxf_isaac_messages.so, not found
undefined reference to `cudaFree@libcudart.so.12'
undefined reference to `cudaMemPoolGetAttribute'
```

**Cause:** NVIDIA's precompiled binaries (`.so` files you can't recompile yourself) were built with CUDA 12, but the machine only has CUDA 13 — release-3.1 was released before CUDA 13 launched, so many binaries are still tied to CUDA 12.

**Fix:** Install CUDA 12.6 alongside CUDA 13 (they can coexist without conflict):

```bash
sudo apt install cuda-toolkit-12-6
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/targets/x86_64-linux/lib:${LD_LIBRARY_PATH}' >> ~/.bashrc
source ~/.bashrc
```

### Error 3: `Failed <<< isaac_ros_image_proc` (part of `isaac_ros_image_pipeline`)

**Topic 4:** `isaac_ros_image_proc` (part of `isaac_ros_image_pipeline`)

#### Error 4.1: `nvcv/Tensor.hpp: No such file or directory` (found in `pad_node.cpp`)

```
fatal error: nvcv/Tensor.hpp: No such file or directory
    32 | #include "nvcv/Tensor.hpp"
```

**Cause:** This is a CV-CUDA header, which isn't distributed via a standard apt repo — it must be downloaded as a `.deb` directly from GitHub Releases.

**Fix:**

```bash
cd ~/Downloads
wget https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb
wget https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
sudo dpkg -i cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb
sudo dpkg -i cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
sudo apt --fix-broken install  # if dependencies are missing
```

> **Note:** Choose the `-cuda12-` file (not `-cuda13-`) to match the other compat libraries using the CUDA 12 runtime (see Topic 3.4).

---

*(Document continues — next topic: Apriltag)*
