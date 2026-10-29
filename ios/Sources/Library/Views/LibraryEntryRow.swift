//
//  LibraryEntryRow.swift
//  MyApp
//
//  Card view for library entries in the list.
//

import SwiftUI

struct LibraryEntryRow: View {
    let entry: LibraryEntry
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                entryImage
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(formatDate(entry.publishDate))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var entryImage: some View {
        if let imageURL = entry.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholderImage
                case .success(let image):
                    image
                        .resizable()
                case .failure:
                    placeholderImage
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.05))

            Image(systemName: "cube.transparent")
                .font(.system(size: 30, weight: .thin))
                .foregroundColor(.white.opacity(0.2))
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Supporting Views

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }
}

struct CategoryPill: View {
    let category: String

    var body: some View {
        Text(formatCategoryName(category))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(category.categoryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(category.categoryColor.opacity(0.15))
            .cornerRadius(12)
    }
}

#Preview {
    LibraryEntryRow(
        entry: LibraryEntry(
            id: "test",
            title: "Getting Started with Your App",
            summary: "Learn how to make the most of all the features available to you.",
            contentURL: "https://example.com/content.md",
            publishDate: Date(),
            expiryDate: nil,
            category: "getting_started",
            imageURL: nil,
            featured: true,
            version: "1.0"
        ),
        viewModel: LibraryViewModel()
    )
    .frame(width: 300, height: 260)
    .padding()
}
