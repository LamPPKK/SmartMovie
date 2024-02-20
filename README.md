# Tùng Lâm Smart Movie App

The Tùng Lâm Smart Movie App, powered by The Movie Database (TMDb) API, is an innovative iOS application designed to bring the latest movie trends to your fingertips. It showcases a curated selection of trending movies, providing users with a seamless and interactive way to discover new films and delve into detailed information about their favorites.

## Key Features

- **Discover Trending Movies:** Stay updated with a dynamically curated list of trending movies. Explore popular and highly-rated films from a wide range of genres.
- **In-depth Movie Details:** Get access to comprehensive movie information including titles, detailed descriptions, release dates, and user ratings, all in one place.

## Built With

The app is crafted using state-of-the-art technologies and frameworks:

- **Swift:** The primary programming language for iOS app development, known for its power and efficiency.
- **UIKit Framework:** A foundational framework that provides the necessary UI components for designing intuitive user interfaces.
- **TMDb API:** Utilizes The Movie Database API to fetch and display up-to-date movie information and images, ensuring a rich and informative user experience.

## Getting Started

### Installation

1. Clone the GitHub repository to your local machine:
   ```
   git clone https://github.com/LamPPKK/SmartMovie.git
   ```
2. Open the project in Xcode by navigating to the cloned directory and selecting the project file.
3. Build and run the application on your chosen simulator or physical iOS device to start exploring the world of movies.

### Configuration

Personalize the app with your TMDb API key by following these steps:

1. Navigate to the `APIConnection.swift` file within the project.
2. Find the placeholder `YOUR_API` and replace it with your personal TMDb API key:
   ```swift
   class APIConnection {
       let defaultSession = URLSession(configuration: URLSessionConfiguration.default)
       var dataTask: URLSessionDataTask?
       private let domain = "YOUR_API_KEY_HERE" // Replace YOUR_API_KEY_HERE with your actual API key
   }
   ```
3. Save the file to apply the changes.

## License

The Tùng Lâm Smart Movie App is available under the :P License, allowing for both personal and commercial use. Feel free to modify, distribute, and utilize the code as you see fit.

## Acknowledgments

- A special thank you to The Movie Database (TMDb) for providing the essential movie data that powers our app, enabling us to deliver up-to-date and engaging content to our users.
