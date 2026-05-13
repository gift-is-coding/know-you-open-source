import SwiftUI

struct MyWikiDetailView: View {
    let entry: MyWikiEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let entry {
                Text(entry.category.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.54))

                Text(entry.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                Text(entry.summary.isEmpty ? "暂无摘要。" : entry.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if entry.sourceNames.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("来源")
                            .font(.headline)
                            .foregroundStyle(.white)

                        ForEach(entry.sourceNames, id: \.self) { sourceName in
                            Label(sourceName, systemImage: "doc.plaintext")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .padding(.top, 10)
                }
            } else {
                Label("选择一条 My Wiki 内容", systemImage: "sidebar.right")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("这里会显示人物、项目、主题、偏好、待办或总结的详情。")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96))
    }
}
