import os
import sys
import time
import json
import math
import subprocess
import threading
import traceback
import tkinter as tk
from tkinter import ttk, filedialog
from obswebsocket import obsws, events, requests

APP_NAME = "SpreadJam"
APP_VERSION = "1.1.0"
TEXT_PREFIX = "SJ%d  "
VID_EXTS = ('.mp4', '.mpg', '.mkv', '.m4v', '.mov')
FREE_JAM = 99
CONFIG_FILE = "spreadjam_config.json"

BG_MAIN = "#1e1e1e"
BG_SUB = "#2d2d2d"
FG_MAIN = "#ffffff"
FG_SUB = "#b5b5b5"
BG_BTN = "#007acc"

class SpreadJamApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"{APP_NAME} {APP_VERSION}")
        self.root.geometry("400x350")
        self.root.config(bg=BG_MAIN)
        self.root.resizable(False, False)
        
        self.duration_hours = tk.IntVar(value=24)
        self.count_down = tk.BooleanVar(value=False)
        self.folder_path = tk.StringVar(value="")
        self.obs_host = tk.StringVar(value="localhost")
        self.obs_port = tk.StringVar(value="4455")
        self.obs_password = tk.StringVar(value="")
        
        self.seconds_count = 0
        self.seconds_recorded = 0.0
        self.is_recording = False
        self.is_calculating = False
        self.recording_start_time = 0.0
        self.ws = None
        self.connected = False
        
        self._drag_x = 0
        self._drag_y = 0
        
        self.setup_styles()
        self.setup_ui()
        self.load_config()
        self.set_config_ui_state(False)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.update_loop()

    def setup_styles(self):
        self.style = ttk.Style()
        self.style.theme_use("clam")
        self.style.configure(
            "TCombobox",
            fieldbackground=BG_SUB,
            background=BG_MAIN,
            foreground=FG_MAIN,
            arrowcolor=FG_MAIN,
            bordercolor="#444444",
            lightcolor="#444444",
            darkcolor="#444444"
        )
        self.style.map("TCombobox",
            fieldbackground=[("readonly", BG_SUB), ("active", BG_SUB), ("disabled", BG_MAIN)],
            foreground=[("readonly", FG_MAIN), ("active", FG_MAIN), ("disabled", FG_SUB)],
            background=[("readonly", BG_MAIN), ("active", BG_MAIN), ("disabled", BG_MAIN)]
        )
        self.root.option_add("*TCombobox*Listbox.background", BG_SUB)
        self.root.option_add("*TCombobox*Listbox.foreground", FG_MAIN)
        self.root.option_add("*TCombobox*Listbox.selectBackground", BG_BTN)
        self.root.option_add("*TCombobox*Listbox.selectForeground", FG_MAIN)

    def setup_ui(self):
        self.options_frame = tk.Frame(self.root, bg=BG_MAIN)
        self.options_frame.pack(fill="both", expand=True)
        
        title_label = tk.Label(self.options_frame, text=f"{APP_NAME} {APP_VERSION}", font=("Arial", 16, "bold"), bg=BG_MAIN, fg=FG_MAIN)
        title_label.pack(pady=10)
        
        self.obs_frame = tk.LabelFrame(self.options_frame, text=" OBS WebSocket Connection ", bg=BG_MAIN, fg=FG_SUB, padx=10, pady=10, bd=1, relief="solid")
        self.obs_frame.pack(fill="x", padx=15, pady=5)
        
        tk.Label(self.obs_frame, text="Host:", bg=BG_MAIN, fg=FG_MAIN).grid(row=0, column=0, sticky="w")
        self.host_entry = tk.Entry(self.obs_frame, textvariable=self.obs_host, width=12, bg=BG_SUB, fg=FG_MAIN, disabledbackground=BG_MAIN, disabledforeground=FG_SUB, insertbackground=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", highlightcolor=BG_BTN)
        self.host_entry.grid(row=0, column=1, sticky="w", pady=2)
        
        tk.Label(self.obs_frame, text="Port:", bg=BG_MAIN, fg=FG_MAIN).grid(row=0, column=2, sticky="w", padx=5)
        self.port_entry = tk.Entry(self.obs_frame, textvariable=self.obs_port, width=6, bg=BG_SUB, fg=FG_MAIN, disabledbackground=BG_MAIN, disabledforeground=FG_SUB, insertbackground=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", highlightcolor=BG_BTN)
        self.port_entry.grid(row=0, column=3, sticky="w", pady=2)
        
        tk.Label(self.obs_frame, text="Password:", bg=BG_MAIN, fg=FG_MAIN).grid(row=1, column=0, sticky="w")
        self.pass_entry = tk.Entry(self.obs_frame, textvariable=self.obs_password, show="*", width=20, bg=BG_SUB, fg=FG_MAIN, disabledbackground=BG_MAIN, disabledforeground=FG_SUB, insertbackground=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", highlightcolor=BG_BTN)
        self.pass_entry.grid(row=1, column=1, columnspan=3, sticky="we", pady=2)
        
        self.conn_btn = tk.Label(self.options_frame, text="Connect to OBS", bg=BG_BTN, fg=FG_MAIN, font=("Arial", 10, "bold"), bd=0, highlightthickness=1, highlightbackground=BG_MAIN, height=2, relief="flat")
        self.conn_btn.pack(pady=10, fill="x", padx=15)
        
        self.config_frame = tk.LabelFrame(self.options_frame, text=" Configuration ", bg=BG_MAIN, fg=FG_SUB, padx=10, pady=10, bd=1, relief="solid")
        
        tk.Label(self.config_frame, text="Jam Hours:", bg=BG_MAIN, fg=FG_MAIN).grid(row=0, column=0, sticky="w", pady=2)
        self.hours_combo = ttk.Combobox(self.config_frame, textvariable=self.duration_hours, values=[24, 12, 8, 6, FREE_JAM], width=10, state="readonly")
        self.hours_combo.grid(row=0, column=1, sticky="w", pady=2)
        
        self.countdown_check = tk.Checkbutton(self.config_frame, text="Count Down", variable=self.count_down, bg=BG_MAIN, fg=FG_MAIN, selectcolor=BG_SUB, activebackground=BG_MAIN, activeforeground=FG_MAIN)
        self.countdown_check.grid(row=0, column=2, sticky="w", padx=10)
        
        tk.Label(self.config_frame, text="Output Folder:", bg=BG_MAIN, fg=FG_MAIN).grid(row=1, column=0, sticky="w", pady=5)
        self.folder_entry = tk.Entry(self.config_frame, textvariable=self.folder_path, width=16, bg=BG_SUB, readonlybackground=BG_SUB, disabledbackground=BG_MAIN, fg=FG_MAIN, disabledforeground=FG_SUB, insertbackground=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", highlightcolor=BG_BTN, state="readonly")
        self.folder_entry.grid(row=1, column=1, sticky="we", pady=5, padx=(0, 2))
        
        self.refresh_btn = tk.Label(self.config_frame, text="🔄", bg=BG_SUB, fg=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", padx=6, pady=2, font=("Arial", 9), relief="flat")
        self.refresh_btn.grid(row=1, column=2, padx=2)
        
        self.browse_btn = tk.Label(self.config_frame, text="Browse", bg=BG_SUB, fg=FG_MAIN, bd=0, highlightthickness=1, highlightbackground="#444444", padx=6, pady=2, relief="flat")
        self.browse_btn.grid(row=1, column=3, padx=(2, 0))
        
        self.main_timer_label = tk.Label(self.options_frame, text="", font=("Arial", 12, "bold"), bg=BG_MAIN, fg=FG_MAIN)
        self.main_timer_label.pack(pady=10)
        
        self.root.bind("<Button-1>", self.start_drag)
        self.root.bind("<B1-Motion>", self.do_drag)
        
        self.refresh_btn.bind("<Enter>", lambda e: self.refresh_btn.config(bg="#3d3d3d") if self.connected else None)
        self.refresh_btn.bind("<Leave>", lambda e: self.refresh_btn.config(bg=BG_SUB) if self.connected else None)
        self.refresh_btn.bind("<Button-1>", lambda e: self.refresh_folder() if self.connected else None)
        
        self.browse_btn.bind("<Enter>", lambda e: self.browse_btn.config(bg="#3d3d3d") if self.connected else None)
        self.browse_btn.bind("<Leave>", lambda e: self.browse_btn.config(bg=BG_SUB) if self.connected else None)
        self.browse_btn.bind("<Button-1>", lambda e: self.browse_folder() if self.connected else None)
        
        self.conn_btn.bind("<Enter>", self.conn_btn_enter)
        self.conn_btn.bind("<Leave>", self.conn_btn_leave)
        self.conn_btn.bind("<Button-1>", lambda e: self.toggle_connection())

    def conn_btn_enter(self, e):
        if self.connected:
            self.conn_btn.config(bg="#ff4444")
        else:
            self.conn_btn.config(bg="#0098ff")

    def conn_btn_leave(self, e):
        if self.connected:
            self.conn_btn.config(bg="#cc3333")
        else:
            self.conn_btn.config(bg=BG_BTN)

    def set_config_ui_state(self, enabled):
        if enabled:
            self.config_frame.pack(fill="x", padx=15, pady=5)
            self.host_entry.config(state="disabled")
            self.port_entry.config(state="disabled")
            self.pass_entry.config(state="disabled")
        else:
            self.config_frame.pack_forget()
            self.host_entry.config(state="normal")
            self.port_entry.config(state="normal")
            self.pass_entry.config(state="normal")

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f:
                    data = json.load(f)
                    self.obs_host.set(data.get("obs_host", "localhost"))
                    self.obs_port.set(data.get("obs_port", "4455"))
                    self.obs_password.set(data.get("obs_password", ""))
                    self.duration_hours.set(data.get("duration_hours", 24))
                    self.count_down.set(data.get("count_down", False))
                    self.folder_path.set(data.get("folder_path", ""))
            except:
                pass

    def save_config(self):
        data = {
            "obs_host": self.obs_host.get(),
            "obs_port": self.obs_port.get(),
            "obs_password": self.obs_password.get(),
            "duration_hours": self.duration_hours.get(),
            "count_down": self.count_down.get(),
            "folder_path": self.folder_path.get()
        }
        try:
            with open(CONFIG_FILE, "w") as f:
                json.dump(data, f)
        except:
            pass

    def browse_folder(self):
        if not self.connected:
            return
        selected = filedialog.askdirectory()
        if selected:
            self.folder_path.set(selected)
            self.save_config()
            threading.Thread(target=self.calculate_recorded_folder, daemon=True).start()

    def refresh_folder(self):
        if self.connected and self.ws:
            try:
                recdir_resp = self.ws.call(requests.GetRecordDirectory())
                obs_path = recdir_resp.getRecordDirectory()
                if obs_path:
                    self.folder_path.set(obs_path)
                    self.save_config()
            except:
                pass
        threading.Thread(target=self.calculate_recorded_folder, daemon=True).start()

    def start_drag(self, event):
        if not self.is_recording:
            self._drag_x = event.x
            self._drag_y = event.y

    def do_drag(self, event):
        if not self.is_recording:
            x = self.root.winfo_x() + event.x - self._drag_x
            y = self.root.winfo_y() + event.y - self._drag_y
            self.root.geometry(f"+{x}+{y}")

    def toggle_connection(self):
        if not self.connected:
            self.conn_btn.config(text="Connecting...", bg=BG_BTN)
            threading.Thread(target=self.connect_obs, daemon=True).start()
        else:
            self.disconnect_obs()

    def connect_obs(self):
        try:
            host = self.obs_host.get().strip()
            port = int(self.obs_port.get().strip())
            password = self.obs_password.get()
            
            self.ws = obsws(host, port, password)
            self.ws.connect()
            self.ws.register(self.on_record_state_changed, events.RecordStateChanged)
            
            self.connected = True
            self.save_config()
            
            self.root.after(0, lambda: self.conn_btn.config(text="Disconnect from OBS", bg="#cc3333"))
            self.root.after(0, lambda: self.set_config_ui_state(True))
            
            try:
                recdir_resp = self.ws.call(requests.GetRecordDirectory())
                obs_path = recdir_resp.getRecordDirectory()
                if obs_path:
                    self.root.after(0, lambda: self.folder_path.set(obs_path))
            except:
                pass
                
            threading.Thread(target=self.calculate_recorded_folder, daemon=True).start()
            
            status = self.ws.call(requests.GetRecordStatus())
            is_active = False
            if hasattr(status, "datain") and status.datain:
                is_active = status.datain.get("outputActive", status.datain.get("recordActive", False))
            
            if is_active:
                self.root.after(0, self.start_recording)
        except Exception as e:
            traceback.print_exc()
            self.connected = False
            self.root.after(0, lambda: self.conn_btn.config(text="Connection Failed - Retry", bg="#cc3333"))
            self.root.after(0, lambda: self.set_config_ui_state(False))

    def disconnect_obs(self):
        if self.ws:
            try:
                self.ws.disconnect()
            except:
                pass
        self.connected = False
        self.conn_btn.config(text="Connect to OBS", bg=BG_BTN)
        self.set_config_ui_state(False)
        self.stop_recording()

    def on_record_state_changed(self, event):
        active = event.getOutputActive()
        if active:
            self.root.after(0, self.start_recording)
        else:
            self.root.after(0, self.stop_recording)

    def get_video_duration(self, filepath):
        try:
            env = os.environ.copy()
            if sys.platform == "darwin":
                env["PATH"] = env.get("PATH", "") + ":/opt/homebrew/bin:/usr/local/bin"
            cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filepath]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
            return float(result.stdout.strip())
        except:
            return 0.0

    def calculate_recorded_folder(self):
        self.is_calculating = True
        total_time = 0.0
        path = self.folder_path.get()
        if path and os.path.exists(path):
            for entry in os.scandir(path):
                try:
                    if entry.is_file() and entry.name.lower().endswith(VID_EXTS):
                        if self.is_recording and self.recording_start_time > 0:
                            if entry.stat().st_mtime >= self.recording_start_time - 10:
                                continue
                        total_time += self.get_video_duration(entry.path)
                except:
                    pass
        self.seconds_recorded = total_time
        self.is_calculating = False

    def start_recording(self):
        if hasattr(self, 'timer_label'):
            return
        self.is_recording = True
        self.recording_start_time = time.time()
        self.seconds_count = 0
        self.save_config()
        
        threading.Thread(target=self.calculate_recorded_folder, daemon=True).start()
        
        self.options_frame.pack_forget()
        self.root.overrideredirect(True)
        
        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        w = 160
        h = 26
        self.root.geometry(f"{w}x{h}+5+{sh - h - 5}")
        
        self.root.config(bg="#000000")
        self.timer_label = tk.Label(self.root, font=("Arial", 12, "bold"), fg="#ffffff", bg="#000000", anchor="w", padx=4)
        self.timer_label.pack(fill="both", expand=True)
        self.root.attributes("-topmost", True)

    def stop_recording(self):
        if not self.is_recording:
            return
        self.is_recording = False
        self.recording_start_time = 0.0
        
        if hasattr(self, 'timer_label'):
            self.timer_label.pack_forget()
            self.timer_label.destroy()
            del self.timer_label
        
        self.options_frame.pack(fill="both", expand=True)
        self.root.overrideredirect(False)
        self.root.attributes("-topmost", False)
        self.root.config(bg=BG_MAIN)
        
        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        x = (sw - 400) // 2
        y = (sh - 350) // 2
        self.root.geometry(f"400x350+{x}+{y}")
        
        threading.Thread(target=self.calculate_recorded_folder, daemon=True).start()

    def update_loop(self):
        if self.is_recording:
            if self.connected and self.ws:
                try:
                    status = self.ws.call(requests.GetRecordStatus())
                    time_str = ""
                    if hasattr(status, "datain") and status.datain:
                        time_str = status.datain.get("outputTimecode", status.datain.get("recordTimecode", ""))
                    
                    if time_str:
                        parts = time_str.split(":")
                        self.seconds_count = int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
                except:
                    self.seconds_count += 1
            else:
                self.seconds_count += 1
                
        self.update_display()
        self.root.after(1000, self.update_loop)

    def update_display(self):
        jam_hours = self.duration_hours.get()
        is_freejam = jam_hours == FREE_JAM
        should_count_down = self.count_down.get() and not is_freejam
        seconds_total = jam_hours * 3600
        
        timer_seconds = self.seconds_count + self.seconds_recorded
        if should_count_down:
            timer_seconds = seconds_total - timer_seconds
            
        t_prefix = "" if is_freejam else (TEXT_PREFIX % jam_hours)
        
        if not self.folder_path.get():
            text = f"{t_prefix}Error: Set path"
        elif self.seconds_count == 0 and self.seconds_recorded == 0:
            hour_str = str(jam_hours) if should_count_down else "0"
            text = f"{t_prefix}{hour_str}:00:00"
        elif timer_seconds >= seconds_total and not is_freejam:
            text = f"{t_prefix}■   TIME!"
        else:
            t_hours = int(timer_seconds // 3600)
            t_minutes = int((timer_seconds % 3600) // 60)
            t_seconds = int(timer_seconds % 60)
            text = f"{t_prefix}{t_hours:02d}:{t_minutes:02d}:{t_seconds:02d}"
            
            if not self.is_recording:
                text += "  II"
            elif self.is_calculating:
                text += "  ○"
            elif t_seconds % 2 == 0:
                text += "  ●"
                
        if hasattr(self, 'timer_label'):
            self.timer_label.config(text=text)
        if hasattr(self, 'main_timer_label'):
            if self.connected:
                self.main_timer_label.config(text=text)
            else:
                self.main_timer_label.config(text="")

    def on_close(self):
        self.disconnect_obs()
        self.root.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = SpreadJamApp(root)
    root.mainloop()