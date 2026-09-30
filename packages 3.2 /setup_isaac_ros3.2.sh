set -e

WS=$HOME/workspaces/isaac_ros-dev
BRANCH=release-3.2
STEP=0
step() { STEP=$((STEP+1)); echo; echo "===== [$STEP] $1 ====="; }

# ===== 0. Preflight =====
step "Preflight check"
[ -f /opt/ros/humble/setup.bash ] || { echo "ไม่พบ ROS 2 Humble (/opt/ros/humble)"; exit 1; }
command -v nvidia-smi >/dev/null || { echo "ไม่พบ nvidia-smi (ยังไม่ได้ลง NVIDIA driver)"; exit 1; }

# ถ้าไม่มี CUDA toolkit (ไม่มี nvcc) -> ติดตั้ง CUDA 12.6 toolkit ให้ (ตรงกับ JetPack 6.x)
if [ ! -x /usr/local/cuda/bin/nvcc ]; then
  echo "ไม่พบ CUDA toolkit -> จะติดตั้ง cuda-toolkit-12-6"

  # เช็คว่า driver รองรับ CUDA >= 12.6
  DRV_CUDA=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' | head -1)
  echo "Driver รองรับ CUDA สูงสุด: ${DRV_CUDA:-unknown}"
  if [ -n "$DRV_CUDA" ] && [ "$(printf '%s\n' 12.6 "$DRV_CUDA" | sort -V | head -1)" != "12.6" ]; then
    echo "Driver เก่าเกินไป (ต้องรองรับ CUDA >= 12.6) กรุณาอัปเดต NVIDIA driver ก่อน"
    exit 1
  fi

  # เช็คพื้นที่ดิสก์ (toolkit ใช้ราว 5-8GB)
  FREE_GB=$(df -BG --output=avail /usr/local | tail -1 | tr -dc '0-9')
  [ "${FREE_GB:-0}" -ge 10 ] || { echo "พื้นที่ว่างไม่พอ (เหลือ ${FREE_GB}GB, ต้องการ >= 10GB)"; exit 1; }

  if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
    wget -q -O /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
  fi
  sudo apt update
  # ลงเฉพาะ toolkit ไม่ใช่ metapackage "cuda" (กันไปแตะ driver)
  sudo apt install -y cuda-toolkit-12-6

  # ชี้ /usr/local/cuda ไปที่ 12.6 (ถ้ายังไม่มี หรือเป็น symlink เสีย)
  if [ ! -e /usr/local/cuda ]; then
    sudo ln -sfn /usr/local/cuda-12.6 /usr/local/cuda
  fi
fi
/usr/local/cuda/bin/nvcc --version | tail -1

CUDA_ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')
echo "GPU arch: sm_${CUDA_ARCH} | CUDA: $(readlink -f /usr/local/cuda)"

# ===== Locale =====
step "Locale"
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# ===== Base deps =====
step "Base dependencies"
sudo apt update && sudo apt install -y gnupg wget curl software-properties-common git
sudo add-apt-repository -y universe

# ===== Isaac ROS apt repo (release-3.2) =====
step "Isaac ROS apt repository (3.2)"
wget -qO - https://isaac.download.nvidia.com/isaac-ros/repos.key | sudo apt-key add -
ISAAC_LINE="deb https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) release-3.2"
grep -qxF "$ISAAC_LINE" /etc/apt/sources.list || echo "$ISAAC_LINE" | sudo tee -a /etc/apt/sources.list
sudo apt-get update

# ===== ros-dev-tools =====
step "ros-dev-tools"
sudo apt install -y ros-dev-tools

# ===== VPI =====
step "VPI (key ตรงจาก NVIDIA กัน keyserver timeout)"
wget -qO - https://repo.download.nvidia.com/jetson/jetson-ota-public.asc | sudo apt-key add -
VPI_LINE="deb https://repo.download.nvidia.com/jetson/x86_64/jammy r36.4 main"
grep -rqF "jetson/x86_64/jammy r36.4" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || \
  sudo add-apt-repository -y "$VPI_LINE"
sudo apt update
sudo apt install -y libnvvpi3 vpi3-dev

# ===== CUDA 12.6 runtime only =====
step "CUDA 12.6 runtime (cudart เท่านั้น)"
sudo apt install -y cuda-cudart-12-6

# ===== nvToolsExt (linking) =====
step "libnvToolsExt"
sudo apt install -y libnvtoolsext1
sudo ln -sf /usr/lib/x86_64-linux-gnu/libnvToolsExt.so.1 /usr/lib/x86_64-linux-gnu/libnvToolsExt.so
sudo ldconfig

# ===== CV-CUDA =====
step "CV-CUDA (cuda12)"
if ! dpkg -s cvcuda-dev >/dev/null 2>&1 && ! dpkg -l | grep -q cvcuda; then
  mkdir -p ~/Downloads && cd ~/Downloads
  wget -nc https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb
  wget -nc https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
  sudo dpkg -i cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
  sudo apt --fix-broken install -y
  rm -f ~/Downloads/cvcuda-*.deb
else
  echo "CV-CUDA ติดตั้งแล้ว ข้าม"
fi

# ===== Environment variables =====
# สำคัญ: ต้อง export ใน script นี้โดยตรง เพราะ 'source ~/.bashrc' ใช้ไม่ได้ใน non-interactive shell
step "Environment variables"
CUDA12_LIB=/usr/local/cuda-12.6/targets/x86_64-linux/lib
CCCL_INC=/usr/local/cuda/targets/x86_64-linux/include/cccl

export ISAAC_ROS_WS=$WS/
export CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${CUDA12_LIB}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CPLUS_INCLUDE_PATH=${CCCL_INC}${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}
export C_INCLUDE_PATH=${CCCL_INC}${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}
export CMAKE_PREFIX_PATH=/opt/nvidia/vpi3${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}

if ! grep -q "# --- isaac_ros env ---" ~/.bashrc; then
cat >> ~/.bashrc << 'ENV_END'
# --- isaac_ros env ---
export ISAAC_ROS_WS=${HOME}/workspaces/isaac_ros-dev/
export CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda-12.6/targets/x86_64-linux/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CPLUS_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}
export C_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}
export CMAKE_PREFIX_PATH=/opt/nvidia/vpi3${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}
# --- end isaac_ros env ---
ENV_END
fi

# ===== Workspace + clone =====
step "Workspace + clone ($BRANCH)"
mkdir -p $WS/src
cd $WS/src
[ -d isaac_ros_common ]         || git clone -b $BRANCH https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
[ -d isaac_ros_nitros ]         || git clone -b $BRANCH https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nitros.git
[ -d isaac_ros_image_pipeline ] || git clone -b $BRANCH https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_image_pipeline.git
[ -d isaac_ros_apriltag ]       || git clone -b $BRANCH https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_apriltag.git
[ -d realsense-ros ]            || git clone -b ros2-master https://github.com/IntelRealSense/realsense-ros.git
[ -d negotiated ]               || git clone https://github.com/osrf/negotiated.git

# ===== Launch file =====
step "Launch file (full_camera_pipeline)"
LAUNCH_DIR=$WS/src/isaac_ros_apriltag/isaac_ros_apriltag/launch
mkdir -p $LAUNCH_DIR
cat > $LAUNCH_DIR/full_camera_pipeline.launch.py << 'LAUNCH_END'
import launch
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode


def generate_launch_description():

    apriltag_backend_arg = DeclareLaunchArgument('apriltag_backend', default_value='CUDA')

    realsense_camera_node = ComposableNode(
        package='realsense2_camera',
        plugin='realsense2_camera::RealSenseNodeFactory',
        name='realsense2_camera',
        namespace='',
        parameters=[{
            'color_width': 1920,
            'color_height': 1080,
        }],
        remappings=[('/realsense2_camera/color/image_raw', '/image'),
                    ('/realsense2_camera/color/camera_info', '/camera_info')]
    )

    rectify_node = ComposableNode(
        package='isaac_ros_image_proc',
        plugin='nvidia::isaac_ros::image_proc::RectifyNode',
        name='rectify',
        namespace='',
        parameters=[{
            'output_width': 1920,
            'output_height': 1080,
        }]
    )

    apriltag_node = ComposableNode(
        package='isaac_ros_apriltag',
        plugin='nvidia::isaac_ros::apriltag::AprilTagNode',
        name='apriltag',
        namespace='',
        parameters=[{
            'backend': LaunchConfiguration('apriltag_backend'),
        }]
    )

    full_pipeline_container = ComposableNodeContainer(
        package='rclcpp_components',
        name='full_camera_pipeline_container',
        namespace='',
        executable='component_container_mt',
        composable_node_descriptions=[
            realsense_camera_node,
            rectify_node,
            apriltag_node,
        ],
        output='screen'
    )

    return launch.LaunchDescription([
        apriltag_backend_arg,
        full_pipeline_container,
    ])
LAUNCH_END

# ===== rosdep =====
step "rosdep"
source /opt/ros/humble/setup.bash
pip3 install posix_ipc
sudo rosdep init 2>/dev/null || true
rosdep update
cd $WS
# rosdep จะ error ค้างเรื่อง negotiated/posix_ipc (ปกติ ไม่กระทบ) จึงต้อง || true ไม่ให้ set -e ตัดจบ
rosdep install --from-paths src --ignore-src -r -y || echo "[warn] rosdep มี error บางตัว (คาดไว้แล้ว: negotiated/posix_ipc)"

# ===== Build =====
step "colcon build (sm_${CUDA_ARCH}, parallel-workers 1)"
cd $WS
source /opt/ros/humble/setup.bash
colcon build --symlink-install \
  --cmake-args -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
  --parallel-workers 1

# ===== Source overlay =====
step "Source overlay"
SRC_LINE="source $WS/install/setup.bash"
grep -qxF "$SRC_LINE" ~/.bashrc || echo "$SRC_LINE" >> ~/.bashrc
source $WS/install/setup.bash

echo
echo "===== เสร็จสิ้น ====="
ros2 pkg list | grep apriltag
echo "รันด้วย: ros2 launch isaac_ros_apriltag full_camera_pipeline.launch.py"
source ~/.bashrc
