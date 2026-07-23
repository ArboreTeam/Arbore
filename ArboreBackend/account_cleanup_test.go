package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRemoveLegacyCommunityImageDeletesOnlySupportedFileInConfiguredDirectory(t *testing.T) {
	directory := t.TempDir()
	t.Setenv("COMMUNITY_UPLOADS_DIR", directory)

	imagePath := filepath.Join(directory, "legacy-post.png")
	require.NoError(t, os.WriteFile(imagePath, []byte("image"), 0o600))

	removeLegacyCommunityImage("https://api.arbore.app/uploads/community/legacy-post.png")

	_, err := os.Stat(imagePath)
	require.ErrorIs(t, err, os.ErrNotExist)
}

func TestRemoveLegacyCommunityImageRejectsUnexpectedExtension(t *testing.T) {
	directory := t.TempDir()
	t.Setenv("COMMUNITY_UPLOADS_DIR", directory)

	modelPath := filepath.Join(directory, "keep.usdz")
	require.NoError(t, os.WriteFile(modelPath, []byte("model"), 0o600))

	removeLegacyCommunityImage("../../keep.usdz")

	_, err := os.Stat(modelPath)
	require.NoError(t, err)
}
