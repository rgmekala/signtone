"""
Signtone - Organizer Admin Dashboard
======================================
Streamlit web app for event organizers.
Connects to the FastAPI backend via HTTP.

Pages:
    1_events.py       - create and manage events
    2_signals.py      - create beacons and download .wav files
    3_registrations.py - view attendee profiles
    4_sweepstakes.py  - manage draws
"""

import streamlit as st

# ── Page config ───────────────────────────────────────────────────────────────
st.set_page_config(
    page_title  = "Signtone Dashboard",
    page_icon   = "🎵",
    layout      = "wide",
    initial_sidebar_state = "expanded",
)

# ── Shared API base URL ───────────────────────────────────────────────────────
API_BASE = "http://localhost:8000"

# ── Home page ─────────────────────────────────────────────────────────────────
st.title("🎵 Signtone")
st.subheader("Organizer Dashboard")
st.markdown("---")

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.info("### 📅 Events\nCreate and manage your events")
    if st.button("Go to Events", use_container_width=True):
        st.switch_page("pages/1_events.py")

with col2:
    st.info("### 📡 Signals\nCreate beacons and download .wav files")
    if st.button("Go to Signals", use_container_width=True):
        st.switch_page("pages/2_signals.py")

with col3:
    st.info("### 👥 Registrations\nView attendee profiles")
    if st.button("Go to Registrations", use_container_width=True):
        st.switch_page("pages/3_registrations.py")

with col4:
    st.info("### 🎁 Sweepstakes\nManage draws and winners")
    if st.button("Go to Sweepstakes", use_container_width=True):
        st.switch_page("pages/4_sweepstakes.py")

st.markdown("---")

# ── API health check ──────────────────────────────────────────────────────────
import requests

st.subheader("System Status")
col_a, col_b = st.columns(2)

with col_a:
    try:
        resp = requests.get(f"{API_BASE}/health", timeout=3)
        if resp.status_code == 200:
            data = resp.json()
            st.success(f"✅ API Online - {data.get('service')} v{data.get('version')}")
        else:
            st.error(f"❌ API returned status {resp.status_code}")
    except Exception as e:
        st.error(f"❌ API Offline - {e}")
        st.info("Make sure the backend is running: `make api`")

with col_b:
    st.info("📖 API Docs: [http://localhost:8000/docs](http://localhost:8000/docs)")
