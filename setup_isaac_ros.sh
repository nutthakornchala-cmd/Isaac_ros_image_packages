#!/bin/bash
set -e

# ===== 1. Locale =====
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# ===== 2. Dependencies พื้นฐาน =====
sudo apt update && sudo apt install -y gnupg wget curl software-properties-common
sudo add-apt-repository -y universe

# ===== 3. Isaac ROS Apt Repository =====
wget -qO - https://isaac.download.nvidia.com/isaac-ros/repos.key | sudo apt-key add -
grep -qxF "deb https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) legacy-release-3.1" /etc/apt/sources.list || \
echo "deb https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) legacy-release-3.1" | sudo tee -a /etc/apt/sources.list
sudo apt-get update

# ===== 4. ros-dev-tools =====
sudo apt install -y ros-dev-tools

# ===== 5. VPI (key ตรงจาก NVIDIA กัน keyserver timeout) =====
wget -qO - https://repo.download.nvidia.com/jetson/jetson-ota-public.asc | sudo apt-key add -
sudo add-apt-repository -y 'deb https://repo.download.nvidia.com/jetson/x86_64/jammy r36.4 main'
sudo apt update
sudo apt install -y libnvvpi3 vpi3-dev

# ===== 6. CUDA 12.6 — runtime lib เท่านั้น (กันดิสก์เต็ม) =====
sudo apt install -y cuda-cudart-12-6

# ===== 7. nvToolsExt =====
sudo apt install -y libnvtoolsext1
sudo ln -sf /usr/lib/x86_64-linux-gnu/libnvToolsExt.so.1 /usr/lib/x86_64-linux-gnu/libnvToolsExt.so
sudo ldconfig

# ===== 8. CV-CUDA =====
mkdir -p ~/Downloads && cd ~/Downloads
wget -nc https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb
wget -nc https://github.com/CVCUDA/CV-CUDA/releases/download/v0.16.0/cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
sudo dpkg -i cvcuda-lib-0.16.0-cuda12-x86_64-linux.deb cvcuda-dev-0.16.0-cuda12-x86_64-linux.deb
sudo apt --fix-broken install -y
rm -f ~/Downloads/*.deb

# ===== 9. Environment Variables =====
cat >> ~/.bashrc << 'ENV_END'
export ISAAC_ROS_WS=${HOME}/workspaces/isaac_ros-dev/
export CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CPLUS_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl:${CPLUS_INCLUDE_PATH}
export C_INCLUDE_PATH=/usr/local/cuda/targets/x86_64-linux/include/cccl:${C_INCLUDE_PATH}
export CMAKE_PREFIX_PATH=/opt/nvidia/vpi3:${CMAKE_PREFIX_PATH}
ENV_END
source ~/.bashrc

# ===== 10. Workspace + Clone (ข้ามถ้ามีอยู่แล้ว) =====
mkdir -p ~/workspaces/isaac_ros-dev/src
cd ~/workspaces/isaac_ros-dev/src
[ -d isaac_ros_common ] || git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git
[ -d isaac_ros_nitros ] || git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nitros.git
[ -d isaac_ros_image_pipeline ] || git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_image_pipeline.git
[ -d isaac_ros_apriltag ] || git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_apriltag.git
[ -d realsense-ros ] || git clone https://github.com/IntelRealSense/realsense-ros.git -b ros2-master
[ -d negotiated ] || git clone https://github.com/osrf/negotiated.git

# ===== 11. rosdep =====
pip3 install posix_ipc
sudo rosdep init || true
rosdep update
cd ~/workspaces/isaac_ros-dev
rosdep install --from-paths src --ignore-src -r -y

# ===== 12. Build (ต้องอยู่ root ของ workspace เท่านั้น ไม่ใช่ src/) =====
cd ~/workspaces/isaac_ros-dev
colcon build --symlink-install --cmake-args -DCMAKE_CUDA_ARCHITECTURES=86 --parallel-workers 1

# ===== 13. Source overlay =====
echo "source ~/workspaces/isaac_ros-dev/install/setup.bash" >> ~/.bashrc
source ~/workspaces/isaac_ros-dev/install/setup.bash

# ===== 14. สร้าง Camera Pipeline Launch File =====
# RealSense -> Rectify -> AprilTag (ตัด stereo/pointcloud ออก เพราะต้องการ node แปลง
# image format เพิ่มเติมที่ยังไม่มีในระบบ ใส่กลับเข้ามาได้ทีหลังถ้าต้องการ)
cat > ~/full_camera_pipeline.launch.py << 'LAUNCH_END'
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

echo "===== เสร็จสิ้น ====="
ros2 pkg list | grep apriltag
echo "===== Launch file: ~/full_camera_pipeline.launch.py ====="
echo "===== รันด้วย: ros2 launch ~/full_camera_pipeline.launch.py ====="
