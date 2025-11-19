import { useCallback, useEffect, useRef, useState } from "react";

export type RecordingState = "idle" | "recording" | "paused";

export interface UseMediaRecorderResult {
  recordingState: RecordingState;
  duration: number;
  startRecording: (stream: MediaStream, qualityFactor?: number, audioBitrate?: number) => void;
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

  // Check if MediaRecorder is supported
  const isSupported = typeof MediaRecorder !== "undefined";

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
    (stream: MediaStream, qualityFactor: number = 1.0, audioBitrate: number = 128) => {
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

        // Calculate bitrate based on quality factor (matching server-side calculation)
        // Base bitrate ranges from 512 kbps (low) to 8000 kbps (high) - updated for Very High support
        // Quality factor multiplies this: 0.1 = ~1.3Mbps, 0.5 = ~4.3Mbps, 1.0 = ~8.5Mbps, 1.5 = ~11.7Mbps
        const baseBitrateLow = 512000;    // 512 kbps in bps
        const baseBitrateHigh = 8000000;  // 8000 kbps in bps (increased from 2000)
        const calculatedBitrate = baseBitrateLow + (baseBitrateHigh - baseBitrateLow) * qualityFactor;

        // Use calculated bitrate directly (no artificial minimum)
        const videoBitrate = Math.floor(calculatedBitrate);

        // Convert audio bitrate from kbps to bps
        const audioBitrateInBps = audioBitrate * 1000;

        console.info(`[MediaRecorder] Using video bitrate: ${(videoBitrate / 1000000).toFixed(2)} Mbps (quality factor: ${qualityFactor}), audio bitrate: ${audioBitrate} kbps`);

        // Create MediaRecorder with optimal settings
        const recorder = new MediaRecorder(stream, {
          mimeType,
          videoBitsPerSecond: videoBitrate,
          audioBitsPerSecond: audioBitrateInBps,
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

        console.info("[MediaRecorder] Recording started", { mimeType });
      } catch (err) {
        console.error("[MediaRecorder] Failed to start recording:", err);
        setError(err instanceof Error ? err.message : "Failed to start recording");
        setRecordingState("idle");
      }
    },
    [isSupported]
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
