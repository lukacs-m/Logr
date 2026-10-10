import SwiftUI

struct LogDisclosureGroup<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let content: Content
    let label: Label

    init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        _isExpanded = isExpanded
        self.content = content()
        self.label = label()
    }

    var body: some View {
        #if os(tvOS) || os(watchOS)
        VStack(alignment: .leading) {
            label
            if isExpanded {
                content
            }
        }
        #else
        DisclosureGroup(isExpanded: $isExpanded) { content } label: { label }
        #endif
    }
}

struct LogActionsMenu<Label: View, Content: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let label: Label

    var body: some View {
        #if os(watchOS)
        NavigationLink { List { content } } label: { label }
        #else
        Menu { content } label: { label }
        #endif
    }
}

extension LogActionsMenu where Label == Text {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}
