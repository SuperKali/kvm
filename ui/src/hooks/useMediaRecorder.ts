import { useCallback, useEffect, useRef, useState } from "react";
import { useSettingsStore } from "./stores";

export type RecordingState = "idle" | "recording" | "paused";

export interface UseMediaRecorderResult {
  recordingState: RecordingState;
  duration: number;
  startRecording: (stream: MediaStream) => void;
  stopRecording: () => void;
  pauseRecording: () => void;
  resumeRecording: () => void;
  isSupported: boolean;
  error: string | null;
}

export default function useMediaRecorder(): UseMediaRecorderResult {
  const [recordingState, setRecordingState] = useState<RecordingState>("idle");
  const [duration, setDuration] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startTimeRef = useRef<number>(0);
  const timerRef = useRef<number | null>(null);

  // Get stream quality from settings
  const { streamQuality } = useSettingsStore();

  // Check if MediaRecorder is supported
  const isSupported = typeof MediaRecorder !== "undefined";

  // Calculate video bitrate based on quality factor (same formula as backend)
  const calculateVideoBitrate = (qualityFactor: number): number => {
    const BASE_BITRATE_HIGH = 8000; // Kbps
    const BASE_BITRATE_LOW = 1000; // Kbps

    const baseBitrate = BASE_BITRATE_LOW + (BASE_BITRATE_HIGH - BASE_BITRATE_LOW) * qualityFactor;
    return baseBitrate * 1000; // Convert to bps
  };

  // Update duration timer
  useEffect(() => {
    if (recordingState === "recording") {
      timerRef.current = window.setInterval(() => {
        setDuration(Math.floor((Date.now() - startTimeRef.current) / 1000));
      }, 1000);
    } else {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    }

    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, [recordingState]);

  // Start recording
  const startRecording = useCallback(
    (stream: MediaStream) => {
      if (!isSupported) {
        setError("MediaRecorder is not supported in this browser");
        return;
      }

      if (!stream) {
        setError("No media stream available");
        return;
      }

      try {
        // Clear previous chunks
        chunksRef.current = [];
        setError(null);

        // Determine supported MIME type
        let mimeType = "video/webm;codecs=vp8,opus";

        if (!MediaRecorder.isTypeSupported(mimeType)) {
          mimeType = "video/webm";
        }

        // Calculate bitrate based on current quality setting
        const videoBitrate = calculateVideoBitrate(streamQuality);

        // Create MediaRecorder with quality-matched settings
        const recorder = new MediaRecorder(stream, {
          mimeType,
          videoBitsPerSecond: videoBitrate, // Matches stream quality setting
          audioBitsPerSecond: 128000,       // 128 kbps - matches device output
        });

        // Collect data chunks
        recorder.ondataavailable = (event) => {
          if (event.data && event.data.size > 0) {
            chunksRef.current.push(event.data);
          }
        };

        // Handle recording stop
        recorder.onstop = () => {
          const blob = new Blob(chunksRef.current, { type: mimeType });
          const url = URL.createObjectURL(blob);

          // Create download link
          const a = document.createElement("a");
          a.style.display = "none";
          a.href = url;
          a.download = `jetkvm-session-${new Date().toISOString().replace(/[:.]/g, "-")}.webm`;

          document.body.appendChild(a);
          a.click();

          // Cleanup
          setTimeout(() => {
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
          }, 100);

          // Reset state
          setRecordingState("idle");
          setDuration(0);
          chunksRef.current = [];
        };

        // Handle errors
        recorder.onerror = (event) => {
          console.error("MediaRecorder error:", event);
          setError("Recording error occurred");
          setRecordingState("idle");
        };

        // Start recording with 1-second chunks
        recorder.start(1000);
        mediaRecorderRef.current = recorder;

        startTimeRef.current = Date.now();
        setRecordingState("recording");

        console.info("[MediaRecorder] Recording started", {
          mimeType,
          videoBitrate: `${(videoBitrate / 1000000).toFixed(1)} Mbps`,
          qualityFactor: streamQuality
        });
      } catch (err) {
        console.error("[MediaRecorder] Failed to start recording:", err);
        setError(err instanceof Error ? err.message : "Failed to start recording");
        setRecordingState("idle");
      }
    },
    [isSupported, streamQuality]
  );

  // Stop recording
  const stopRecording = useCallback(() => {
    if (mediaRecorderRef.current && recordingState !== "idle") {
      try {
        mediaRecorderRef.current.stop();

        // Note: We intentionally don't stop the original tracks here
        // as they are still being used for the live stream

        console.info("[MediaRecorder] Recording stopped");
      } catch (err) {
        console.error("[MediaRecorder] Error stopping recording:", err);
        setError("Failed to stop recording");
      }
    }
  }, [recordingState]);

  // Pause recording
  const pauseRecording = useCallback(() => {
    if (mediaRecorderRef.current && recordingState === "recording") {
      try {
        mediaRecorderRef.current.pause();
        setRecordingState("paused");
        console.info("[MediaRecorder] Recording paused");
      } catch (err) {
        console.error("[MediaRecorder] Error pausing recording:", err);
        setError("Failed to pause recording");
      }
    }
  }, [recordingState]);

  // Resume recording
  const resumeRecording = useCallback(() => {
    if (mediaRecorderRef.current && recordingState === "paused") {
      try {
        mediaRecorderRef.current.resume();
        setRecordingState("recording");
        console.info("[MediaRecorder] Recording resumed");
      } catch (err) {
        console.error("[MediaRecorder] Error resuming recording:", err);
        setError("Failed to resume recording");
      }
    }
  }, [recordingState]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (mediaRecorderRef.current && recordingState !== "idle") {
        mediaRecorderRef.current.stop();
      }
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, [recordingState]);

  return {
    recordingState,
    duration,
    startRecording,
    stopRecording,
    pauseRecording,
    resumeRecording,
    isSupported,
    error,
  };
}
