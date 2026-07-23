package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"os"
	"time"
)

func fetchUnsplashImageURLs(ctx context.Context, query string, count int) []string {
	accessKey := os.Getenv("UNSPLASH_ACCESS_KEY")
	if accessKey == "" {
		log.Println("❌ Clé UNSPLASH_ACCESS_KEY manquante")
		return []string{}
	}

	var urls []string
	client := &http.Client{Timeout: 8 * time.Second}
	for i := 0; i < count; i++ {
		apiURL := url.URL{
			Scheme: "https",
			Host:   "api.unsplash.com",
			Path:   "/photos/random",
		}
		parameters := apiURL.Query()
		parameters.Set("query", query)
		parameters.Set("client_id", accessKey)
		apiURL.RawQuery = parameters.Encode()

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL.String(), nil)
		if err != nil {
			log.Println("❌ Requête Unsplash invalide:", err)
			continue
		}
		// The scheme and host are constants; only encoded query values vary.
		resp, err := client.Do(req) //nolint:gosec
		if err != nil {
			log.Println("❌ Erreur requête Unsplash:", err)
			continue
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			_ = resp.Body.Close()
			log.Printf("❌ Unsplash returned HTTP %d", resp.StatusCode) //nolint:gosec
			continue
		}

		var result struct {
			Urls struct {
				Regular string `json:"regular"`
			} `json:"urls"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			log.Println("❌ Erreur parsing JSON Unsplash:", err)
			if closeErr := resp.Body.Close(); closeErr != nil {
				log.Println("Error closing response body:", closeErr)
			}
			continue
		}
		if closeErr := resp.Body.Close(); closeErr != nil {
			log.Println("Error closing response body:", closeErr)
		}
		urls = append(urls, result.Urls.Regular)
	}

	if len(urls) == 0 {
		return []string{"https://source.unsplash.com/featured/?plant"}
	}

	return urls
}
