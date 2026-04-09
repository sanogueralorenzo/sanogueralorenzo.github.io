package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultListenAddr  = ":8080"
	defaultBaseURL     = "https://api.openai.com/v1/audio/transcriptions"
	defaultTimeout     = 60 * time.Second
	defaultMaxUpload   = int64(25 * 1024 * 1024)
	defaultContentType = "application/json"
)

type config struct {
	listenAddr            string
	baseURL               string
	openAITranscribeModel string
	openAIAPIKey          string
	chatGPTBearerToken    string
	chatGPTAccountID      string
	timeout               time.Duration
	maxUploadBytes        int64
}

type server struct {
	cfg        config
	httpClient *http.Client
}

type transcribeResponse struct {
	Text string `json:"text"`
}

func main() {
	loadDotEnv(".env")

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	s := server{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: cfg.timeout,
		},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("POST /v1/transcribe", s.transcribe)

	log.Printf("voice-backend listening on %s", cfg.listenAddr)
	if err := http.ListenAndServe(cfg.listenAddr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func (s server) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s server) transcribe(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.maxUploadBytes)
	if err := r.ParseMultipartForm(s.cfg.maxUploadBytes); err != nil {
		http.Error(w, fmt.Sprintf("invalid multipart form: %v", err), http.StatusBadRequest)
		return
	}

	file, fileHeader, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "missing multipart file field 'file'", http.StatusBadRequest)
		return
	}
	defer file.Close()

	bodyBytes, contentType, err := s.buildUpstreamMultipart(file, fileHeader, r.FormValue("model"))
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to build upstream payload: %v", err), http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.baseURL, bytes.NewReader(bodyBytes))
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to create upstream request: %v", err), http.StatusInternalServerError)
		return
	}
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("User-Agent", "voice-backend/0.1")

	bearer, err := s.resolveBearerToken()
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	req.Header.Set("Authorization", "Bearer "+bearer)

	if isChatGPTTranscribeEndpoint(s.cfg.baseURL) && s.cfg.chatGPTAccountID != "" {
		req.Header.Set("ChatGPT-Account-Id", s.cfg.chatGPTAccountID)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		http.Error(w, fmt.Sprintf("upstream request failed: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed reading upstream response: %v", err), http.StatusBadGateway)
		return
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		http.Error(
			w,
			fmt.Sprintf("upstream error (%d): %s", resp.StatusCode, truncateForError(respBody)),
			http.StatusBadGateway,
		)
		return
	}

	text := extractTranscriptionText(resp.Header.Get("Content-Type"), respBody)
	writeJSON(w, http.StatusOK, transcribeResponse{Text: text})
}

func (s server) buildUpstreamMultipart(
	file multipart.File,
	fileHeader *multipart.FileHeader,
	overrideModel string,
) ([]byte, string, error) {
	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	part, err := writer.CreateFormFile("file", fileHeader.Filename)
	if err != nil {
		return nil, "", err
	}
	if _, err := io.Copy(part, file); err != nil {
		return nil, "", err
	}

	if !isChatGPTTranscribeEndpoint(s.cfg.baseURL) {
		model := strings.TrimSpace(overrideModel)
		if model == "" {
			model = strings.TrimSpace(s.cfg.openAITranscribeModel)
		}
		if model == "" {
			return nil, "", errors.New("OPENAI_TRANSCRIBE_MODEL is empty")
		}
		if err := writer.WriteField("model", model); err != nil {
			return nil, "", err
		}
	}

	if err := writer.Close(); err != nil {
		return nil, "", err
	}

	return buf.Bytes(), writer.FormDataContentType(), nil
}

func (s server) resolveBearerToken() (string, error) {
	if isChatGPTTranscribeEndpoint(s.cfg.baseURL) {
		token := strings.TrimSpace(s.cfg.chatGPTBearerToken)
		if token == "" {
			token = strings.TrimSpace(s.cfg.openAIAPIKey)
		}
		if token == "" {
			return "", errors.New("missing token: set CHATGPT_BEARER_TOKEN (or OPENAI_API_KEY)")
		}
		return token, nil
	}

	token := strings.TrimSpace(s.cfg.openAIAPIKey)
	if token == "" {
		return "", errors.New("missing OPENAI_API_KEY")
	}
	return token, nil
}

func loadConfig() (config, error) {
	baseURL := firstNonEmpty(os.Getenv("BASE_URL"), defaultBaseURL)
	if _, err := url.ParseRequestURI(baseURL); err != nil {
		return config{}, fmt.Errorf("invalid BASE_URL: %w", err)
	}

	listenAddr := strings.TrimSpace(os.Getenv("LISTEN_ADDR"))
	if listenAddr == "" {
		port := strings.TrimSpace(firstNonEmpty(os.Getenv("VOICE_BACKEND_PORT"), os.Getenv("PORT")))
		if port == "" {
			listenAddr = defaultListenAddr
		} else {
			listenAddr = ":" + port
		}
	}

	timeout := defaultTimeout
	if raw := strings.TrimSpace(os.Getenv("REQUEST_TIMEOUT_MS")); raw != "" {
		ms, err := strconv.Atoi(raw)
		if err != nil || ms <= 0 {
			return config{}, fmt.Errorf("invalid REQUEST_TIMEOUT_MS: %q", raw)
		}
		timeout = time.Duration(ms) * time.Millisecond
	}

	maxUploadBytes := defaultMaxUpload
	if raw := strings.TrimSpace(os.Getenv("MAX_UPLOAD_BYTES")); raw != "" {
		value, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || value <= 0 {
			return config{}, fmt.Errorf("invalid MAX_UPLOAD_BYTES: %q", raw)
		}
		maxUploadBytes = value
	}

	return config{
		listenAddr:            listenAddr,
		baseURL:               baseURL,
		openAITranscribeModel: strings.TrimSpace(os.Getenv("OPENAI_TRANSCRIBE_MODEL")),
		openAIAPIKey:          strings.TrimSpace(os.Getenv("OPENAI_API_KEY")),
		chatGPTBearerToken:    strings.TrimSpace(os.Getenv("CHATGPT_BEARER_TOKEN")),
		chatGPTAccountID:      strings.TrimSpace(os.Getenv("CHATGPT_ACCOUNT_ID")),
		timeout:               timeout,
		maxUploadBytes:        maxUploadBytes,
	}, nil
}

func isChatGPTTranscribeEndpoint(rawURL string) bool {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	host := strings.ToLower(parsed.Hostname())
	return host == "chat.openai.com" || host == "chatgpt.com" || strings.Contains(parsed.Path, "/backend-api/transcribe")
}

func extractTranscriptionText(contentType string, body []byte) string {
	if strings.Contains(strings.ToLower(contentType), "application/json") {
		var payload map[string]any
		if err := json.Unmarshal(body, &payload); err == nil {
			if value, ok := payload["text"].(string); ok {
				return value
			}
		}
	}
	return strings.TrimSpace(string(body))
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", defaultContentType)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func loadDotEnv(path string) {
	content, err := os.ReadFile(path)
	if err != nil {
		return
	}

	for _, line := range strings.Split(string(content), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		_ = os.Setenv(key, strings.Trim(value, `"'`))
	}
}

func truncateForError(body []byte) string {
	const max = 600
	trimmed := strings.TrimSpace(string(body))
	if len(trimmed) <= max {
		return trimmed
	}
	return trimmed[:max] + "..."
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
