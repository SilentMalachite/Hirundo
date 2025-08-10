import Foundation

// Page model
public struct Page {
    public let title: String
    public let slug: String
    public let url: String
    public let description: String?
    public let content: String
    
    public init(title: String, slug: String, url: String, description: String? = nil, content: String) {
        self.title = title
        self.slug = slug
        self.url = url
        self.description = description
        self.content = content
    }
}

// Post model
public struct Post {
    public let title: String
    public let slug: String
    public let url: String
    public let date: Date
    public let author: String?
    public let description: String?
    public let categories: [String]
    public let tags: [String]
    public let content: String
    
    public init(
        title: String,
        slug: String,
        url: String,
        date: Date,
        author: String? = nil,
        description: String? = nil,
        categories: [String] = [],
        tags: [String] = [],
        content: String
    ) {
        self.title = title
        self.slug = slug
        self.url = url
        self.date = date
        self.author = author
        self.description = description
        self.categories = categories
        self.tags = tags
        self.content = content
    }
}