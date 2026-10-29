//
//  LibraryView.swift
//  MyApp
//
//  Main library view with category filtering and search.
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""
    @State private var showingSearchBar = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                    .zIndex(2)
                
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    LoadingView()
                } else if viewModel.errorMessage != nil && viewModel.entries.isEmpty {
                    ErrorView(
                        errorMessage: viewModel.errorMessage ?? "Unknown error",
                        onRetry: { viewModel.fetchEntries(forceRefresh: true) }
                    )
                } else {
                    contentView
                }
            }
        }
        .onAppear {
            viewModel.fetchEntries()
            Analytics.trackScreenView("LibraryView")
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trails")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .tracking(-0.3)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation {
                            showingSearchBar.toggle()
                            if !showingSearchBar {
                                searchText = ""
                                viewModel.searchText = ""
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Button(action: { viewModel.fetchEntries(forceRefresh: true) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            
            if showingSearchBar {
                SearchBar(text: $searchText, onCommit: {
                    viewModel.searchText = searchText
                })
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
        }
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color.black.opacity(0.4))
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.filteredEntries.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.filteredEntries) { entry in
                            NavigationLink(destination: LibraryDetailView(entry: entry, viewModel: viewModel)) {
                                LibraryEntryRow(entry: entry, viewModel: viewModel)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.bottom, 80) // Space for bottom filters
        }
        .overlay(alignment: .bottom) {
            categoryFilters
                .padding(.bottom, 12)
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CategoryFilterButton(
                    title: "ALL",
                    isSelected: viewModel.selectedCategory == nil
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.resetCategory()
                    }
                }

                ForEach(viewModel.availableCategories, id: \.self) { category in
                    CategoryFilterButton(
                        title: viewModel.displayNameForCategory(category).uppercased(),
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if viewModel.selectedCategory == category {
                                viewModel.selectedCategory = nil
                            } else {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }

    @State private var isAnimatingEmptyState = false

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 100)

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 60, weight: .thin))
                .foregroundColor(.white.opacity(0.3))
                .offset(y: isAnimatingEmptyState ? -8 : 0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimatingEmptyState)
                .onAppear {
                    isAnimatingEmptyState = true
                }

            Text("No Captures Found")
                .font(.headline)
                .foregroundColor(.white)

            Text("Try clearing your search or filters.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Supporting Views

struct SearchBar: View {
    @Binding var text: String
    var onCommit: () -> Void = {}

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))

            TextField("", text: $text, onCommit: onCommit)
                .placeholder(when: text.isEmpty) {
                    Text("Search captures...").foregroundColor(.white.opacity(0.4))
                }
                .foregroundColor(.white)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onCommit()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.12))
        .cornerRadius(12)
    }
}

struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
                .padding()
            Text("Accessing Library...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
    }
}

struct ErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundColor(.red.opacity(0.8))

            VStack(spacing: 8) {
                Text("Connection Error")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(errorMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 32)
            }

            Button(action: onRetry) {
                Text("RETRY")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    LibraryView()
}
