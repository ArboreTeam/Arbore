package main

import (
	"context"
	"encoding/json"
	"fmt"
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
		encodedQuery := url.QueryEscape(query)
		apiURL := fmt.Sprintf("https://api.unsplash.com/photos/random?query=%s&client_id=%s", encodedQuery, accessKey)

		// nolint:gosec // Dynamic URL is required for Unsplash API with user query
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
		if err != nil {
			log.Println("❌ Requête Unsplash invalide:", err)
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			log.Println("❌ Erreur requête Unsplash:", err)
			continue
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			_ = resp.Body.Close()
			log.Printf("❌ Unsplash returned HTTP %d", resp.StatusCode)
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
