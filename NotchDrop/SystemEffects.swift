// SystemEffects.swift
// NotchEvery
//
// 系统副作用边界（工单 04）：锁屏 / 唤醒前置查询 / 密码存取与注入 / 解锁验证 /
// 告警 / 通知 / 屏幕状态查询。
//
// live 实现是 SystemInteractionService.shared；测试注入假实现，第一次把
// 「注入 → 双验证 → 失败降级 → 告警」跑通并可断言。
// 取密码也在边界内：tryUnlock 整条链卡在取密码后面，不含它则“注入成功”永远不可测。
// 为此 live 端多了两处最小改动（逻辑零变化）：fetchPassword 去掉 `= false` 默认
// （协议方法不允许默认值），以及一个 3 行转发方法（取密码逻辑仍在 SecurityService，
// 因该方法原本就长在 SecurityService 身上）。
// 本次唯一新建的接缝；verifyUnlock 在 live 端是 @MainActor 方法，
// 作为 async 协议方法的 witness 合法（await 时 hop），调用方本就全在主线程。
//
// 注意 fetchPassword 也在边界内：tryUnlock 的整条执行链卡在取密码这一步，
// 不把它含进来，“注入成功”就永远不可测。live 语义（含 warn 弹框）原样保留。

import Foundation

protocol SystemEffects {
    func isScreenLocked(screenState: ScreenState?) -> Bool
    func isSecureToInject(screenState: ScreenState?) -> Bool
    func verifyUnlock(timeout: TimeInterval, notificationTimeout: TimeInterval) async -> SystemInteractionService.UnlockNotification
    func showPasswordMismatchAlert()
    func showAXRevokedAlertIfNeeded(lastAlertTime: inout Date)
    func notifyLock(reason: String)
    func lockOrSaveScreen(useScreensaver: Bool, sleepDisplayAfter: Bool)
    func injectPasswordWithPrelude(_ string: String, isSecureCheck: @escaping () -> Bool) -> Bool
    func showAbnormalUnlockAlert(count: Int, window: Int)
    func clearLockNotification()
    func fetchPassword(warn: Bool) -> Result<String?, KeychainError>
}

extension SystemInteractionService: SystemEffects {}
