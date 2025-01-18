#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <linux/bpf.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <zygisk.hpp>
#include <fstream>
#include <sstream>
#include <vector>
#include <sys/stat.h>
#include <fcntl.h>
#include <chrono>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>

using namespace zygisk;

// 性能数据结构
struct PerformanceMetrics {
    double fps;
    double cpu_usage;
    double gpu_usage;
    double memory_usage;
    double temperature;
    std::chrono::system_clock::time_point timestamp;
};

// 性能监控器
class PerformanceMonitor {
public:
    PerformanceMonitor() : running_(false) {}
    
    void start() {
        running_ = true;
        monitor_thread_ = std::thread(&PerformanceMonitor::monitorLoop, this);
    }
    
    void stop() {
        running_ = false;
        if (monitor_thread_.joinable()) {
            monitor_thread_.join();
        }
    }
    
    PerformanceMetrics getLatestMetrics() {
        std::lock_guard<std::mutex> lock(metrics_mutex_);
        return latest_metrics_;
    }

private:
    void monitorLoop() {
        while (running_) {
            PerformanceMetrics metrics = collectMetrics();
            
            {
                std::lock_guard<std::mutex> lock(metrics_mutex_);
                latest_metrics_ = metrics;
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(1000));
        }
    }
    
    PerformanceMetrics collectMetrics() {
        PerformanceMetrics metrics;
        metrics.timestamp = std::chrono::system_clock::now();
        
        // 收集CPU使用率
        std::ifstream stat_file("/proc/stat");
        if (stat_file.is_open()) {
            std::string line;
            std::getline(stat_file, line);
            std::istringstream ss(line);
            std::string cpu_label;
            unsigned long user, nice, system, idle;
            ss >> cpu_label >> user >> nice >> system >> idle;
            
            unsigned long total = user + nice + system + idle;
            if (prev_total_ > 0) {
                unsigned long diff_total = total - prev_total_;
                unsigned long diff_idle = idle - prev_idle_;
                metrics.cpu_usage = 100.0 * (diff_total - diff_idle) / diff_total;
            }
            prev_total_ = total;
            prev_idle_ = idle;
        }
        
        // 收集GPU使用率（需要设备特定实现）
        metrics.gpu_usage = 0.0;
        
        // 收集内存使用率
        std::ifstream meminfo_file("/proc/meminfo");
        if (meminfo_file.is_open()) {
            unsigned long total_mem = 0, free_mem = 0;
            std::string line;
            while (std::getline(meminfo_file, line)) {
                if (line.find("MemTotal:") == 0) {
                    std::istringstream(line.substr(9)) >> total_mem;
                } else if (line.find("MemAvailable:") == 0) {
                    std::istringstream(line.substr(13)) >> free_mem;
                }
            }
            if (total_mem > 0) {
                metrics.memory_usage = 100.0 * (total_mem - free_mem) / total_mem;
            }
        }
        
        // 收集温度
        std::ifstream temp_file("/sys/class/thermal/thermal_zone0/temp");
        if (temp_file.is_open()) {
            int temp;
            temp_file >> temp;
            metrics.temperature = temp / 1000.0;
        }
        
        return metrics;
    }

    std::atomic<bool> running_;
    std::thread monitor_thread_;
    std::mutex metrics_mutex_;
    PerformanceMetrics latest_metrics_;
    unsigned long prev_total_ = 0;
    unsigned long prev_idle_ = 0;
};

class EbpfInterceptor : public ModuleBase {
public:
    void onLoad() override {
        // 初始化性能监控
        monitor_.start();
        
        interceptSyscall(__NR_bpf, [this](SyscallContext& ctx) {
            // 收集性能数据
            auto metrics = monitor_.getLatestMetrics();
            logPerformance(metrics);
            
            return handleBpfSyscall(ctx);
        });
    }
    
    ~EbpfInterceptor() {
        monitor_.stop();
    }
    
private:
    void logPerformance(const PerformanceMetrics& metrics) {
        std::ofstream log_file("/data/adb/modules/fas-rs/performance.log", std::ios::app);
        if (log_file.is_open()) {
            auto time_t = std::chrono::system_clock::to_time_t(metrics.timestamp);
            log_file << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S") << ","
                     << metrics.fps << ","
                     << metrics.cpu_usage << ","
                     << metrics.gpu_usage << ","
                     << metrics.memory_usage << ","
                     << metrics.temperature << "\n";
        }
        
        // 将性能数据写入配置文件
        std::ofstream config_file("/data/adb/modules/fas-rs/performance.toml");
        if (config_file.is_open()) {
            config_file << "[current]\n"
                       << "fps = " << metrics.fps << "\n"
                       << "cpu_usage = " << metrics.cpu_usage << "\n"
                       << "gpu_usage = " << metrics.gpu_usage << "\n"
                       << "memory_usage = " << metrics.memory_usage << "\n"
                       << "temperature = " << metrics.temperature << "\n";
        }
    }
    
    PerformanceMonitor monitor_;

private:
    static long handleBpfSyscall(SyscallContext& ctx) {
        struct utsname uts;
        uname(&uts);
        int major, minor;
        sscanf(uts.release, "%d.%d", &major, &minor);

        if (major < 5 || (major == 5 && minor < 10)) {
            return handleLegacyKernel(ctx);
        }

        return ctx.callOriginal();
    }

    static long handleLegacyKernel(SyscallContext& ctx) {
        if (getenv("ZYGISK_EMULATE_CPUFREQ")) {
            int cpu = ctx.arg<int>(0);
            unsigned int min_freq = ctx.arg<unsigned int>(1);
            unsigned int max_freq = ctx.arg<unsigned int>(2);
            
            // 检查CPU是否存在
            std::string cpu_dir = "/sys/devices/system/cpu/cpu" + std::to_string(cpu);
            if (access(cpu_dir.c_str(), F_OK) != 0) {
                return -ENODEV;
            }
            
            // 检查cpufreq是否可用
            std::string cpufreq_dir = cpu_dir + "/cpufreq";
            if (access(cpufreq_dir.c_str(), F_OK) != 0) {
                // 尝试通过sysfs直接设置
                std::string min_path = "/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/cpufreq/scaling_min_freq";
                std::string max_path = "/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/cpufreq/scaling_max_freq";
                
                if (access(min_path.c_str(), W_OK) == 0 && access(max_path.c_str(), W_OK) == 0) {
                    std::ofstream min_file(min_path);
                    std::ofstream max_file(max_path);
                    
                    if (min_file.is_open() && max_file.is_open()) {
                        min_file << min_freq;
                        max_file << max_freq;
                        return 0;
                    }
                }
                return -ENOSYS;
            }
            
            // 获取可用频率
            std::vector<unsigned int> freqs;
            std::string avail_freqs;
            std::ifstream avail_file(cpufreq_dir + "/scaling_available_frequencies");
            if (avail_file.is_open()) {
                std::string line;
                while (std::getline(avail_file, line)) {
                    std::stringstream ss(line);
                    unsigned int freq;
                    while (ss >> freq) {
                        freqs.push_back(freq);
                    }
                }
            }
            
            // 如果没有可用频率表，尝试从其他路径获取
            if (freqs.empty()) {
                std::ifstream cpuinfo_max("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq");
                std::ifstream cpuinfo_min("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq");
                
                unsigned int max, min;
                if (cpuinfo_max >> max && cpuinfo_min >> min) {
                    freqs.push_back(min);
                    freqs.push_back(max);
                }
            }
            
            // 验证频率范围
            if (!freqs.empty()) {
                std::sort(freqs.begin(), freqs.end());
                if (min_freq < freqs.front() || max_freq > freqs.back()) {
                    return -EINVAL;
                }
            }
            
            // 应用频率限制
            std::string min_path = cpufreq_dir + "/scaling_min_freq";
            std::string max_path = cpufreq_dir + "/scaling_max_freq";
            
            std::ofstream min_file(min_path);
            std::ofstream max_file(max_path);
            
            if (min_file.is_open() && max_file.is_open()) {
                min_file << min_freq;
                max_file << max_freq;
                
                // 记录当前设置
                std::string clamp_file = "/data/adb/modules/fas-rs/cpu" + std::to_string(cpu) + "_clamp";
                std::ofstream clamp(clamp_file);
                if (clamp.is_open()) {
                    clamp << min_freq << " " << max_freq;
                }
                
                return 0;
            }
            
            return -EIO;
        }
        return ctx.callOriginal();
    }
};

REGISTER_ZYGISK_MODULE(EbpfInterceptor);