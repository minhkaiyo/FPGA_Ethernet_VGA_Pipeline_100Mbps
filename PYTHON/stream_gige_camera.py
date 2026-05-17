# stream_gige_camera.py
# Mo ta: Stream GigE Camera (VimbaPython 1.2.1) den FPGA qua UDP 100Mbps
# Fix: Gui 1 row/packet de tuong thich voi eth_pixel_rx.v tren FPGA
#      Format: [row_idx: 2B big-endian] [pixel_data: WIDTH bytes]
#      => Moi goi UDP = 2 + 640 = 642 bytes (nam gon trong MTU 1500)
# Ngay: 16/05/2026

import vimba
import socket
import struct
import time
import numpy as np
import cv2
import queue
import threading

# --- CONFIG ---
FPGA_IP    = "255.255.255.255"  # Broadcast
FPGA_PORT  = 1234
WIDTH      = 640
HEIGHT     = 480
CAM_ID     = 'DEV_000F315CE51C'
TARGET_FPS = 60   # 1Gbps RGMII: 60 FPS * 480 * 642 * 8 = 148.4 Mbps << 1000Mbps ✓
SEND_DELAY = 0.0  # Delay giua cac goi (0 = gui lien tuc)

# Queue chuyen anh tu Callback thread sang Main thread (hien thi OpenCV)
frame_queue = queue.Queue(maxsize=2)

# Queue chuyen du lieu raw tu Callback sang TX thread (gui UDP)
tx_queue = queue.Queue(maxsize=4)


def tx_worker(sock, addr):
    """Luong rieng gui du lieu UDP row-by-row, tuong thich voi eth_pixel_rx.v."""
    while True:
        item = tx_queue.get()
        if item is None:
            break  # Tin hieu ket thuc
        frame_id, img = item

        # Gui tung row — dung format ma FPGA hieu:
        #   [row_idx: 2 bytes big-endian] [pixel_data: 640 bytes]
        for y in range(HEIGHT):
            row_header = struct.pack('>H', y)
            row_data   = img[y, :].tobytes()
            sock.sendto(row_header + row_data, addr)

            if SEND_DELAY > 0:
                time.sleep(SEND_DELAY)

        tx_queue.task_done()


class FrameHandler:
    def __init__(self):
        self.frame_count = 0
        self.frame_id    = 0
        self.t0          = time.time()
        self.skip_count  = 0

    def __call__(self, cam, frame):
        if frame.get_status() == vimba.FrameStatus.Complete:
            # Lay raw ndarray tu Vimba
            raw = frame.as_numpy_ndarray()

            # Fix hien thi: Mono8 co the la (H, W) hoac (H, W, 1)
            if raw.ndim == 3:
                img = raw[:, :, 0]
            else:
                img = raw

            # Crop/pad ve dung kich thuoc
            img = img[:HEIGHT, :WIDTH]

            # GUI UDP (phi blocking - day vao TX queue)
            if not tx_queue.full():
                tx_queue.put_nowait((self.frame_id & 0xFFFF, img.copy()))
            else:
                self.skip_count += 1  # TX busy, skip frame (throttle)

            # HIEN THI OpenCV (phi blocking)
            if not frame_queue.full():
                frame_queue.put_nowait(img.copy())

            # Tra frame lai cho Vimba
            cam.queue_frame(frame)

            # Thong ke FPS
            self.frame_count += 1
            self.frame_id    += 1
            now = time.time()
            if now - self.t0 >= 1.0:
                fps = self.frame_count / (now - self.t0)
                skip_info = f"  Skipped: {self.skip_count}" if self.skip_count > 0 else ""
                print(f"[STREAM] FPS: {fps:.1f}  |  Frame-ID: {self.frame_id}{skip_info}")
                self.frame_count = 0
                self.skip_count  = 0
                self.t0 = now


def main():
    bw_est = TARGET_FPS * HEIGHT * (2 + WIDTH) * 8 / 1_000_000
    print("=== GigE -> FPGA Stream (1 row/packet, 100Mbps) ===")
    print(f"    Target : {FPGA_IP}:{FPGA_PORT}")
    print(f"    Reso   : {WIDTH}x{HEIGHT} Mono8")
    print(f"    Packets: {HEIGHT} packets/frame (1 row each)")
    print(f"    Size   : {2 + WIDTH} bytes/packet")
    print(f"    Est BW : {bw_est:.1f} Mbps @ {TARGET_FPS} FPS")

    # Khoi tao socket UDP
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
    addr = (FPGA_IP, FPGA_PORT)

    # Khoi dong TX thread
    tx_thread = threading.Thread(target=tx_worker, args=(sock, addr), daemon=True)
    tx_thread.start()

    with vimba.Vimba.get_instance() as vmb:
        cams = vmb.get_all_cameras()
        if not cams:
            print("[ERROR] Khong tim thay camera!")
            tx_queue.put(None)
            return

        # Tim dung cam theo ID, fallback ve cam[0]
        cam = cams[0]
        for c in cams:
            if c.get_id() == CAM_ID:
                cam = c
                break

        print(f"[INFO] Camera: {cam.get_id()}")

        with cam:
            def set_feat(name, val):
                try:
                    cam.get_feature_by_name(name).set(val)
                except Exception as e:
                    print(f"  [WARN] '{name}' = {val}: {e}")

            # Cau hinh camera — gioi han FPS de khong qua 100Mbps
            set_feat('PixelFormat', 'Mono8')
            set_feat('Width', WIDTH)
            set_feat('Height', HEIGHT)
            set_feat('ExposureAuto', 'Off')
            set_feat('ExposureTimeAbs', 10000.0)
            set_feat('AcquisitionFrameRateAbs', float(TARGET_FPS))
            print(f"[OK] Camera configured: {WIDTH}x{HEIGHT} Mono8 @ {TARGET_FPS}fps")

            try:
                handler = FrameHandler()
                cam.start_streaming(handler, buffer_count=10)
                print("[RUNNING] Streaming... 'q' in preview to stop.")

                while True:
                    try:
                        img = frame_queue.get(timeout=0.1)
                        display = cv2.resize(img, (800, 600), interpolation=cv2.INTER_NEAREST)
                        cv2.imshow('GigE Camera -> FPGA (100Mbps)', display)
                    except queue.Empty:
                        pass

                    if cv2.waitKey(1) & 0xFF == ord('q'):
                        print("[INFO] User stop.")
                        break

            except KeyboardInterrupt:
                print("\n[INFO] Ctrl+C.")
            except Exception as e:
                print(f"\n[ERROR] {e}")
            finally:
                cam.stop_streaming()
                tx_queue.put(None)
                tx_thread.join(timeout=2)
                cv2.destroyAllWindows()
                sock.close()
                print("[OK] Done.")


if __name__ == "__main__":
    main()
