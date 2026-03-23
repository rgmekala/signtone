"""Signtone Dashboard - Sweepstakes page."""

import random
import requests
import streamlit as st

API_BASE = "http://localhost:8000"

st.set_page_config(
    page_title="Sweepstakes - Signtone",
    page_icon="🎁",
    layout="wide"
)
st.title("🎁 Sweepstakes")
st.markdown("---")

# ── Load public events ────────────────────────────────────────────────────────
try:
    resp   = requests.get(
        f"{API_BASE}/events/",
        params={"event_type": "public"},
        timeout=5
    )
    events = resp.json() if resp.status_code == 200 else []
except Exception:
    events = []

if not events:
    st.info(
        "No public events found. "
        "Create a public event in the Events page to run a sweepstake."
    )
    st.stop()

event_options = {
    f"{ev['name']} ({ev['registration_count']} entries)": ev
    for ev in events
}
selected_label = st.selectbox("Select sweepstake event", list(event_options.keys()))
event          = event_options[selected_label]
event_id       = event["id"]

# ── Event info ────────────────────────────────────────────────────────────────
col1, col2, col3 = st.columns(3)
with col1:
    st.metric("Total Entries", event["registration_count"])
with col2:
    st.metric("Status", event["status"].upper())
with col3:
    max_reg = event.get("max_registrations")
    st.metric("Max Entries", max_reg if max_reg else "Unlimited")

st.markdown("---")

# ── Load entries ──────────────────────────────────────────────────────────────
try:
    resp    = requests.get(
        f"{API_BASE}/events/{event_id}/registrations",
        timeout=5
    )
    data    = resp.json() if resp.status_code == 200 else {}
    entries = data.get("registrations", [])
except Exception as e:
    st.error(f"Failed to load entries: {e}")
    entries = []

if not entries:
    st.info("No entries yet for this sweepstake.")
    st.stop()

# ── Entries list ──────────────────────────────────────────────────────────────
st.subheader(f"Entries - {len(entries)} total")

with st.expander("View all entries"):
    for i, entry in enumerate(entries, 1):
        snap = entry.get("profile_snapshot", {})
        st.write(
            f"{i}. **{snap.get('full_name', 'Unknown')}** - "
            f"{snap.get('email', '')} - "
            f"{entry.get('registered_at', '')[:10]}"
        )

st.markdown("---")

# ── Draw winner ───────────────────────────────────────────────────────────────
st.subheader("🎲 Draw Winner")

num_winners = st.number_input(
    "Number of winners to draw",
    min_value=1,
    max_value=min(10, len(entries)),
    value=1
)

if st.button("🎲 Draw Winner Now", type="primary", use_container_width=True):
    winners = random.sample(entries, k=num_winners)

    st.balloons()
    st.success(f"🎉 {num_winners} winner(s) selected!")
    st.markdown("---")

    for i, winner in enumerate(winners, 1):
        snap = winner.get("profile_snapshot", {})
        st.markdown(f"### 🏆 Winner {i}")

        with st.container(border=True):
            col1, col2 = st.columns([1, 3])
            with col1:
                photo = snap.get("photo_url")
                if photo:
                    st.image(photo, width=80)
                else:
                    st.markdown("👤")
            with col2:
                st.markdown(f"## {snap.get('full_name', 'Unknown')}")
                st.write(f"📧 **Email:** {snap.get('email', '-')}")
                if snap.get("phone"):
                    st.write(f"📞 **Phone:** {snap['phone']}")
                if snap.get("city"):
                    st.write(f"📍 **City:** {snap['city']}")
                st.caption(
                    f"Entered: {winner.get('registered_at', '')[:10]}"
                )

    st.markdown("---")
    st.info(
        "⚠️ Record the winner details above. "
        "Contact them directly to arrange prize delivery. "
        "Signtone does not handle prize fulfilment."
    )
