package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
)

func fetchUnsplashImageURLs(query string, count int) []string {
	accessKey := os.Getenv("UNSPLASH_ACCESS_KEY")
	if accessKey == "" {
		log.Println("❌ Clé UNSPLASH_ACCESS_KEY manquante")
		return []string{}
	}

	var urls []string
	for i := 0; i < count; i++ {
		encodedQuery := url.QueryEscape(query)
		apiURL := fmt.Sprintf("https://api.unsplash.com/photos/random?query=%s&client_id=%s", encodedQuery, accessKey)

		resp, err := http.Get(apiURL)
		if err != nil {
			log.Println("❌ Erreur requête Unsplash:", err)
			continue
		}
		defer resp.Body.Close()

		var result struct {
			Urls struct {
				Regular string `json:"regular"`
			} `json:"urls"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			log.Println("❌ Erreur parsing JSON Unsplash:", err)
			continue
		}
		urls = append(urls, result.Urls.Regular)
	}

	if len(urls) == 0 {
		return []string{"https://source.unsplash.com/featured/?plant"}
	}

	return urls
}
