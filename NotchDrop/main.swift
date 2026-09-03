//
//  main.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Darwin

let productPage = URL(string: "https://github.com/hahappyfu/NotchEvery")!
let sponsorPage = URL(string: "https://github.com/sponsors/hahappyfu")!

let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

// 路径统一走 AppPaths（#26），定义见 AppPaths.swift
// documentsDirectory 同步创建（PID/TrayDrop 依赖），temporary 清理异步（#20）
try? FileManager.default.createDirectory(
    at: AppPaths.documentsDirectory,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700]
)
DispatchQueue.global(qos: .userInitiated).async {
    try? FileManager.default.removeItem(at: AppPaths.temporaryDirectory)
    try? FileManager.default.createDirectory(
        at: AppPaths.temporaryDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
}

// ——— 修复 #11: PID 单例文件加 O_EXCL/O_NOFOLLOW/文件锁 + 修复 #15 权限校验 ———
func secureWritePID() {
    let pid = String(NSRunningApplication.current.processIdentifier)
    guard let data = pid.data(using: .utf8) else { return }
    let path = pidFile.path
    // 1) 若已存在，先用 lstat 校验非 symlink，再尝试读旧 PID 优雅退出旧实例
    var st = stat()
    if lstat(path, &st) == 0 {
        // 是符号链接则直接移除，不跟随
        if (st.st_mode & S_IFMT) == S_IFLNK {
            unlink(path)
        } else {
            if let prevStr = try? String(contentsOf: pidFile, encoding: .utf8),
               let prev = Int(prevStr.trimmingCharacters(in: .whitespacesAndNewlines)),
               let app = NSRunningApplication(processIdentifier: pid_t(prev)),
               app.processIdentifier != NSRunningApplication.current.processIdentifier
            {
                app.terminate()
                // 给旧进程一点退出时间
                Thread.sleep(forTimeInterval: 0.3)
            }
            // 尝试删除旧文件（非跟随，lstat 已确认非链接）
            try? FileManager.default.removeItem(at: pidFile)
        }
    }
    // 2) 以 O_CREAT|O_EXCL|O_NOFOLLOW 原子创建，避免 TOCTOU 与 symlink 攻击
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
    if fd >= 0 {
        defer { close(fd) }
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                _ = write(fd, base, data.count)
            }
        }
    } else if errno == EEXIST {
        // 竞态：另一实例已创建，尝试用 flock 加锁后覆盖
        let fd2 = open(path, O_WRONLY | O_NOFOLLOW)
        if fd2 >= 0 {
            defer { close(fd2) }
            if flock(fd2, LOCK_EX | LOCK_NB) == 0 {
                ftruncate(fd2, 0)
                data.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress { _ = write(fd2, base, data.count) }
                }
                flock(fd2, LOCK_UN)
            }
        }
    }
}

secureWritePID()

// 清理：异常退出时尽力清理 pidFile
atexit {
    try? FileManager.default.removeItem(at: pidFile)
}

_ = TrayDrop.shared
TrayDrop.shared.cleanExpiredFiles()

// ——— 修复 #4: O_EVTONLY FD 泄漏 ———
repeat {
    let executablePath = ProcessInfo.processInfo.arguments.first!
    let selfHandle = open(executablePath, O_EVTONLY)
    guard selfHandle > 0 else { break }

    let monitorSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: selfHandle,
        eventMask: .delete
    )
    monitorSource.setEventHandler {
        guard monitorSource.data == .delete else { return }
        monitorSource.cancel()
        exit(0)
    }
    monitorSource.setCancelHandler {
        close(selfHandle)
    }
    monitorSource.resume()
} while false

private let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
