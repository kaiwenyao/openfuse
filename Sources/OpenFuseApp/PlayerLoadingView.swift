import SwiftUI

/// Shown immediately after tapping Continue Watching. The home page is already
/// gone; resolution and player preparation happen behind this page, which stays
/// interactive (cancel, retry, ⌘Tab).
struct PlayerLoadingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.cancelLoading()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Theme.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .help("取消")
                Spacer()
            }
            .padding(22)

            Spacer()
            VStack(spacing: 14) {
                if let error = model.loadingError {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.secondary)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        // Retrying a record whose source is gone can only fail
                        // again, so that case offers the useful action instead.
                        if !model.loadingFailure.offersRemoveFromHistory {
                            Button("重试") { model.retryLoading() }
                                .buttonStyle(.borderedProminent)
                        }
                        if model.loadingFailure.offersRemoveFromHistory {
                            Button("从历史中移除") { model.removeFailedRecordFromHistory() }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("返回首页") { model.cancelLoading() }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text(model.loadingTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if !model.loadingSubtitle.isEmpty {
                        Text(model.loadingSubtitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                    }
                    Text("正在准备播放…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            Spacer()

            Button("取消") { model.cancelLoading() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
