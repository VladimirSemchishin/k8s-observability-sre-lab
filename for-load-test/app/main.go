package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	httpRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "demo_http_requests_total",
		Help: "HTTP requests (RED: rate / errors).",
	}, []string{"method", "path", "code"})
	httpDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "demo_http_request_duration_seconds",
		Help:    "HTTP request duration (RED: duration).",
		Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 3, 5},
	}, []string{"method", "path"})
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if tp, err := initTracer(ctx); err != nil {
		slog.Error("otel traces disabled", "err", err)
	} else {
		defer func() { _ = tp.Shutdown(context.Background()) }()
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", health)
	mux.Handle("GET /work", traced("GET /work", work))
	mux.Handle("GET /slow", traced("GET /slow", slow))
	mux.Handle("GET /error", traced("GET /error", boom))
	mux.Handle("GET /metrics", promhttp.Handler())

	addr := ":" + getenv("PORT", "8080")
	srv := &http.Server{Addr: addr, Handler: mux}
	go func() {
		slog.Info("listen", "addr", addr, "otlp", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server", "err", err)
			os.Exit(1)
		}
	}()
	<-ctx.Done()
	shut, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shut)
}

func health(w http.ResponseWriter, _ *http.Request) { writeJSON(w, http.StatusOK, map[string]string{"status": "ok"}) }

func work(w http.ResponseWriter, _ *http.Request) {
	n := 0
	for i := 0; i < 25_000; i++ {
		n += i
	}
	time.Sleep(15 * time.Millisecond)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "n": n})
}

func slow(w http.ResponseWriter, _ *http.Request) {
	d := time.Duration(1000+rand.Intn(2000)) * time.Millisecond
	time.Sleep(d)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "delay_ms": d.Milliseconds()})
}

func boom(w http.ResponseWriter, r *http.Request) {
	err := errors.New("intentional failure")
	span := trace.SpanFromContext(r.Context())
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
}

func traced(name string, next http.HandlerFunc) http.Handler {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		start := time.Now()
		next(sw, r)
		path, code := r.URL.Path, strconv.Itoa(sw.code)
		httpRequests.WithLabelValues(r.Method, path, code).Inc()
		httpDuration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
		sc := trace.SpanFromContext(r.Context()).SpanContext()
		slog.Info("request", "method", r.Method, "path", path, "status", sw.code,
			"duration_ms", time.Since(start).Milliseconds(),
			"trace_id", sc.TraceID().String(), "span_id", sc.SpanID().String())
	})
	return otelhttp.NewHandler(inner, name)
}

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
	exp, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, err
	}
	res, err := resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
		resource.WithAttributes(semconv.ServiceName(getenv("OTEL_SERVICE_NAME", "demo-load"))),
	)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})
	return tp, nil
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(c int) { w.code = c; w.ResponseWriter.WriteHeader(c) }

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func getenv(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
