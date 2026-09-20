import { randomBytes } from "node:crypto";
import { MediaStreamTrack, RTCPeerConnection, RtpHeader, RtpPacket } from "werift";
import type { OpusAudio } from "../workspace/audio.js";

export interface RealtimePeer {
  offer(): Promise<string>;
  accept(sdp: string): Promise<void>;
  sendAudio(audio: OpusAudio, signal?: AbortSignal): Promise<void>;
  close(): Promise<void>;
}

export class NodeRealtimePeer implements RealtimePeer {
  private readonly connection = new RTCPeerConnection();
  private readonly track = new MediaStreamTrack({ kind: "audio" });

  constructor() {
    this.connection.addTrack(this.track);
    this.connection.createDataChannel("oai-events");
  }

  async offer(): Promise<string> {
    const offer = await this.connection.createOffer();
    await this.connection.setLocalDescription(offer);
    const sdp = this.connection.localDescription?.sdp;
    if (!sdp) throw new Error("Could not create the voice connection offer.");
    return sdp;
  }

  async accept(sdp: string): Promise<void> {
    await this.connection.setRemoteDescription({ type: "answer", sdp });
    if (this.connection.connectionState !== "connected") {
      await this.connection.connectionStateChange.watch((state) => state === "connected", 15_000);
    }
  }

  async sendAudio(audio: OpusAudio, signal?: AbortSignal): Promise<void> {
    let sequenceNumber = randomBytes(2).readUInt16BE(0);
    let timestamp = randomBytes(4).readUInt32BE(0);
    const ssrc = randomBytes(4).readUInt32BE(0);
    const send = async (data: Buffer, samples: number, durationMs: number) => {
      if (signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      this.track.writeRtp(new RtpPacket(new RtpHeader({
        version: 2,
        payloadType: 111,
        sequenceNumber,
        timestamp,
        ssrc,
        marker: true,
      }), data));
      sequenceNumber = (sequenceNumber + 1) & 0xffff;
      timestamp = (timestamp + samples) >>> 0;
      await new Promise((resolve) => setTimeout(resolve, durationMs));
    };
    for (const frame of audio.frames) await send(frame.data, frame.samples, frame.durationMs);
    const silence = Buffer.from([0xf8, 0xff, 0xfe]);
    for (let index = 0; index < 50; index += 1) await send(silence, 960, 20);
  }

  async close(): Promise<void> {
    await this.connection.close();
  }
}
