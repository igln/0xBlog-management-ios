import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.isConfigured {
                MainTabView()
            } else {
                SettingsView(isInitialSetup: true)
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            PostListView()
                .tabItem {
                    Label("Posts", systemImage: "text.bubble")
                }
            
            CreatePostView()
                .tabItem {
                    Label("New Post", systemImage: "square.and.pencil")
                }
            
            ModerateCommentsView()
                .tabItem {
                    Label("Moderate", systemImage: "checkmark.shield")
                }
            
            SettingsView(isInitialSetup: false)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.cyan)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    let isInitialSetup: Bool
    
    @State private var host: String = ""
    @State private var port: String = "8081"
    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("0xBlog")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Admin Console")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Server Configuration") {
                    TextField("Server Host (e.g., 192.168.1.100)", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
                
                Section("Authentication") {
                    HStack {
                        if showApiKey {
                            TextField("API Key", text: $apiKey)
                                .autocapitalization(.none)
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }
                        
                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section {
                    Button {
                        saveConfiguration()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text(isInitialSetup ? "Connect" : "Save Changes")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
                
                if !isInitialSetup {
                    Section {
                        Button(role: .destructive) {
                            appState.clearConfiguration()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Disconnect")
                                Spacer()
                            }
                        }
                    }
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                }
            }
            .navigationTitle(isInitialSetup ? "Setup" : "Settings")
            .navigationBarTitleDisplayMode(isInitialSetup ? .large : .inline)
            .onAppear {
                loadCurrentValues()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValid: Bool {
        !host.isEmpty && !apiKey.isEmpty && Int(port) != nil
    }
    
    private func loadCurrentValues() {
        host = appState.serverHost
        port = String(appState.serverPort)
        apiKey = appState.apiKey
    }
    
    private func saveConfiguration() {
        guard let portInt = Int(port) else {
            errorMessage = "Invalid port number"
            showError = true
            return
        }
        
        isSaving = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.saveConfiguration(host: host, port: portInt, apiKey: apiKey)
            isSaving = false
        }
    }
}

// MARK: - Post List View

struct PostListView: View {
    @EnvironmentObject var appState: AppState
    @State private var posts: [BlogPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var postToDelete: BlogPost?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && posts.isEmpty {
                    ProgressView("Loading posts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, posts.isEmpty {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadPosts() }
                        }
                    }
                } else if posts.isEmpty {
                    ContentUnavailableView {
                        Label("No Posts", systemImage: "text.bubble")
                    } description: {
                        Text("Create your first post to get started")
                    }
                } else {
                    List {
                        ForEach(posts) { post in
                            PostRowView(post: post)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        postToDelete = post
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .refreshable {
                        await loadPosts()
                    }
                }
            }
            .navigationTitle("Posts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadPosts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadPosts()
            }
            .confirmationDialog(
                "Delete Post",
                isPresented: $showDeleteConfirmation,
                presenting: postToDelete
            ) { post in
                Button("Delete", role: .destructive) {
                    Task { await deletePost(post) }
                }
            } message: { _ in
                Text("Are you sure you want to delete this post?")
            }
        }
    }
    
    private func loadPosts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await BlogAPIClient.shared.getPosts()
            posts = response.posts
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func deletePost(_ post: BlogPost) async {
        do {
            try await BlogAPIClient.shared.deletePost(id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PostRowView: View {
    let post: BlogPost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.content)
                .font(.body)
                .lineLimit(3)
            
            HStack {
                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatDate(post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Create Post View

struct CreatePostView: View {
    @EnvironmentObject var appState: AppState
    @State private var content: String = ""
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    private let maxLength = 280
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .focused($isFocused)
                    .frame(maxHeight: .infinity)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                
                Divider()
                
                HStack {
                    Text("\(content.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundColor(content.count > maxLength ? .red : .secondary)
                    
                    Spacer()
                    
                    Button {
                        Task { await createPost() }
                    } label: {
                        HStack {
                            if isPosting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            }
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(isValid ? Color.cyan : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .disabled(!isValid || isPosting)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        content = ""
                    }
                    .disabled(content.isEmpty)
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your post has been published!")
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.count <= maxLength
    }
    
    private func createPost() async {
        isPosting = true
        
        do {
            _ = try await BlogAPIClient.shared.createPost(content: content.trimmingCharacters(in: .whitespacesAndNewlines))
            content = ""
            showSuccess = true
            isFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isPosting = false
    }
}

// MARK: - Moderate Comments View

struct ModerateCommentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var comments: [BlogComment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && comments.isEmpty {
                    ProgressView("Loading pending comments...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, comments.isEmpty {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadPendingComments() }
                        }
                    }
                } else if comments.isEmpty {
                    ContentUnavailableView {
                        Label("No Pending Comments", systemImage: "checkmark.shield")
                    } description: {
                        Text("All comments have been moderated")
                    } actions: {
                        Button("Refresh") {
                            Task { await loadPendingComments() }
                        }
                    }
                } else {
                    List {
                        Section("Pending Comments (\(comments.count))") {
                            ForEach(comments) { comment in
                                CommentRowView(
                                    comment: comment,
                                    onApprove: { await approveComment(comment) },
                                    onDelete: { await deleteComment(comment) }
                                )
                            }
                        }
                    }
                    .refreshable {
                        await loadPendingComments()
                    }
                }
            }
            .navigationTitle("Moderate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadPendingComments() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadPendingComments()
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func loadPendingComments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await BlogAPIClient.shared.getPendingComments()
            comments = response.comments
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func approveComment(_ comment: BlogComment) async {
        do {
            _ = try await BlogAPIClient.shared.moderateComment(id: comment.id, approve: true)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func deleteComment(_ comment: BlogComment) async {
        do {
            try await BlogAPIClient.shared.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CommentRowView: View {
    let comment: BlogComment
    let onApprove: () async -> Void
    let onDelete: () async -> Void
    
    @State private var isProcessing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("@\(comment.authorName)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan)
                
                Spacer()
                
                Text("Post #\(comment.postId)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(comment.content)
                .font(.body)
            
            HStack {
                Text(formatDate(comment.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    Task {
                        isProcessing = true
                        await onApprove()
                        isProcessing = false
                    }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isProcessing)
                
                Button(role: .destructive) {
                    Task {
                        isProcessing = true
                        await onDelete()
                        isProcessing = false
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
