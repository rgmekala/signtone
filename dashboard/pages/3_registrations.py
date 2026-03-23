"""Signtone Dashboard - Registrations page."""

import requests
import streamlit as st
import pandas as pd

API_BASE = "http://localhost:8000"

st.set_page_config(
    page_title="Registrations - Signtone",
    page_icon="👥",
    layout="wide"
)
st.title("👥 Registrations")
st.markdown("---")

# ── Event selector ────────────────────────────────────────────────────────────
try:
    events_resp = requests.get(f"{API_BASE}/events/", timeout=5)
    events      = events_resp.json() if events_resp.status_code == 200 else []
except Exception:
    events = []

if not events:
    st.warning("No events found.")
    st.stop()

event_options = {
    f"{ev['name']} ({ev['registration_count']} registered)": ev["id"]
    for ev in events
}
selected_label = st.selectbox("Select event", list(event_options.keys()))
event_id       = event_options[selected_label]

# ── Load registrations ────────────────────────────────────────────────────────
try:
    resp = requests.get(
        f"{API_BASE}/events/{event_id}/registrations",
        timeout=5
    )
    data  = resp.json() if resp.status_code == 200 else {}
    regs  = data.get("registrations", [])
    total = data.get("total", 0)
except Exception as e:
    st.error(f"Failed to load registrations: {e}")
    st.stop()

st.subheader(f"{data.get('event_name', '')} - {total} registrations")

if not regs:
    st.info("No registrations yet for this event.")
    st.stop()

# ── Summary metrics ───────────────────────────────────────────────────────────
col1, col2, col3 = st.columns(3)
prof_count = sum(1 for r in regs if r.get("profile_type") == "professional")
pub_count  = total - prof_count

with col1:
    st.metric("Total Registrations", total)
with col2:
    st.metric("LinkedIn Profiles", prof_count)
with col3:
    st.metric("Public Profiles", pub_count)

st.markdown("---")

# ── Profile cards ─────────────────────────────────────────────────────────────
st.subheader("Attendee Profiles")

view = st.radio("View as", ["Cards", "Table"], horizontal=True)

if view == "Cards":
    cols = st.columns(3)
    for i, reg in enumerate(regs):
        snap = reg.get("profile_snapshot", {})
        with cols[i % 3]:
            profile_type = reg.get("profile_type", "public")
            badge = "💼" if profile_type == "professional" else "🎁"

            with st.container(border=True):
                # Photo
                photo = snap.get("photo_url")
                if photo:
                    st.image(photo, width=60)

                st.markdown(f"**{snap.get('full_name', 'Unknown')}** {badge}")

                if snap.get("headline"):
                    st.caption(snap["headline"])
                if snap.get("company"):
                    st.caption(f"🏢 {snap['company']}")

                st.write(f"📧 {snap.get('email', '-')}")

                if snap.get("phone"):
                    st.write(f"📞 {snap['phone']}")
                if snap.get("city"):
                    st.write(f"📍 {snap['city']}")
                if snap.get("profile_url"):
                    st.markdown(
                        f"[LinkedIn Profile]({snap['profile_url']})"
                    )

                st.caption(
                    f"Registered: {reg.get('registered_at', '')[:10]}"
                )

else:
    # Table view
    rows = []
    for reg in regs:
        snap = reg.get("profile_snapshot", {})
        rows.append({
            "Name":         snap.get("full_name", ""),
            "Email":        snap.get("email", ""),
            "Phone":        snap.get("phone", ""),
            "Company":      snap.get("company", ""),
            "Headline":     snap.get("headline", ""),
            "City":         snap.get("city", ""),
            "Profile Type": reg.get("profile_type", ""),
            "Registered":   reg.get("registered_at", "")[:10],
        })

    df = pd.DataFrame(rows)
    st.dataframe(df, use_container_width=True)

    # Export CSV
    csv = df.to_csv(index=False)
    st.download_button(
        label       = "⬇️ Export CSV",
        data        = csv,
        file_name   = f"registrations_{event_id}.csv",
        mime        = "text/csv",
        use_container_width=True,
    )
