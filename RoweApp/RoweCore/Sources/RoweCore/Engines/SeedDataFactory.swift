import Foundation

public enum SeedDataFactory {
    public static func makeInitialWorkspace(now: Date = Date()) -> WorkspaceSnapshot {
        let space = Space(name: "My Space", authorName: "Owner", createdAt: now)

        return WorkspaceSnapshot(
            space: space,
            folders: [],
            tags: [],
            sidebarSections: [
                SidebarSectionState(type: .starred, isVisible: true, isCollapsed: false),
                SidebarSectionState(type: .folders, isVisible: true, isCollapsed: false),
                SidebarSectionState(type: .tags, isVisible: true, isCollapsed: false)
            ],
            documents: [],
            sharedDocuments: [],
            connections: [],
            settings: AppSettings()
        )
    }
}
