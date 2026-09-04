import Foundation

/// Embedded starter files written by `SiteScaffolder`.
enum ScaffoldTemplates {
    static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func configYAML(title: String, includeBlog: Bool) -> String {
        let quotedTitle = yamlQuoted(title)
        // Every blog-derived flag reads from this one binding, so RSS and the three
        // `blog.generate*` switches can never drift apart.
        let blogFlag = includeBlog ? "true" : "false"
        return """
        site:
          title: \(quotedTitle)
          description: "A site built with Hirundo"
          url: "https://example.com"
          language: "en-US"
          author:
            name: "Your Name"
            email: "your.email@example.com"

        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"

        server:
          port: 8080
          liveReload: true

        blog:
          postsPerPage: 10
          generateArchive: \(blogFlag)
          generateCategories: \(blogFlag)
          generateTags: \(blogFlag)

        features:
          sitemap: true
          rss: \(blogFlag)
          searchIndex: false
          minify: false

        """
    }

    static func indexMarkdown(title: String) -> String {
        return """
        ---
        title: "Home"
        template: "default.html"
        ---

        # Welcome to \(title)

        This is your new Hirundo site. Edit this file at `content/index.md`.

        """
    }

    static let aboutMarkdown = """
    ---
    title: "About"
    template: "default.html"
    ---

    # About

    This is the about page. Edit it at `content/about.md`.

    """

    static func baseHTML(includeBlog: Bool) -> String {
        let blogNav = includeBlog ? "\n            <a href=\"/archive/\">Blog</a>" : ""
        return """
        <!DOCTYPE html>
        <html lang="{{ site.language }}">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}</title>
            <link rel="stylesheet" href="/css/style.css">
        </head>
        <body>
            <header>
                <h1><a href="/">{{ site.title }}</a></h1>
                <nav>
                    <a href="/">Home</a>
                    <a href="/about/">About</a>\(blogNav)
                </nav>
            </header>
            <main>
                {% block content %}{% endblock %}
            </main>
            <footer>
                <p>&copy; {{ site.author.name }}</p>
            </footer>
        </body>
        </html>

        """
    }

    static let defaultHTML = """
    {% extends "base.html" %}

    {% block content %}
    <article>
        <h1>{{ page.title }}</h1>
        {{ content }}
    </article>
    {% endblock %}

    """

    static let postHTML = """
    {% extends "base.html" %}

    {% block content %}
    <article>
        <h1>{{ page.title }}</h1>
        <time>{{ page.date | date: "%B %d, %Y" }}</time>
        {% if page.categories %}
        <div class="categories">
            Categories:
            {% for category in page.categories %}
            <a href="/categories/{{ category | slugify }}">{{ category }}</a>
            {% endfor %}
        </div>
        {% endif %}
        {% if page.tags %}
        <div class="tags">
            Tags:
            {% for tag in page.tags %}
            <a href="/tags/{{ tag | slugify }}">{{ tag }}</a>
            {% endfor %}
        </div>
        {% endif %}
        {{ content }}
    </article>
    {% endblock %}

    """

    static let styleCSS = """
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        line-height: 1.6;
        color: #333;
        max-width: 800px;
        margin: 0 auto;
        padding: 20px;
    }

    header {
        margin-bottom: 2rem;
        border-bottom: 1px solid #eee;
        padding-bottom: 1rem;
    }

    header h1 {
        margin: 0;
    }

    header h1 a {
        color: inherit;
        text-decoration: none;
    }

    nav a {
        margin-right: 1rem;
    }

    footer {
        margin-top: 3rem;
        padding-top: 1rem;
        border-top: 1px solid #eee;
        color: #666;
    }

    pre {
        background: #f4f4f4;
        padding: 1rem;
        overflow-x: auto;
    }

    code {
        background: #f4f4f4;
        padding: 2px 4px;
    }

    """

    static let gitignore = """
    _site/
    .DS_Store

    """

    /// The sample blog post written by `--blog`.
    ///
    /// `date` is emitted as ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`), the format
    /// `ContentProcessor` accepts for front-matter dates. It defaults to the moment of
    /// scaffolding so a freshly created site never opens on a stale sample post.
    static func helloWorldPost(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return """
        ---
        title: "Hello World"
        date: \(formatter.string(from: date))
        template: "post.html"
        ---

        # Hello World

        This is your first post. Edit it at `content/posts/hello-world.md`.

        """
    }
}
