"""Signtone Dashboard - Events page."""

import requests
import streamlit as st
from datetime import datetime

API_BASE = "http://localhost:8000"

st.set_page_config(page_title="Events - Signtone", page_icon="📅", layout="wide")
st.title("📅 Events")
st.markdown("---")

tab_list, tab_create = st.tabs(["All Events", "Create Event"])

# ── List events ───────────────────────────────────────────────────────────────
with tab_list:
    st.subheader("Your Events")

    col_filter1, col_filter2 = st.columns(2)
    with col_filter1:
        filter_type = st.selectbox(
            "Filter by type",
            ["All", "professional", "public"]
        )
    with col_filter2:
        filter_status = st.selectbox(
            "Filter by status",
            ["All", "active", "draft", "ended"]
        )

    params = {}
    if filter_type != "All":
        params["event_type"] = filter_type
    if filter_status != "All":
        params["status"] = filter_status

    try:
        resp   = requests.get(f"{API_BASE}/events/", params=params, timeout=5)
        events = resp.json() if resp.status_code == 200 else []
    except Exception as e:
        st.error(f"Failed to load events: {e}")
        events = []

    if not events:
        st.info("No events found. Create one using the 'Create Event' tab.")
    else:
        for ev in events:
            badge = "💼" if ev["event_type"] == "professional" else "🎁"
            status_color = {
                "active":   "🟢",
                "draft":    "🟡",
                "ended":    "🔴",
                "archived": "⚫",
            }.get(ev["status"], "⚪")

            with st.expander(
                f"{badge} {ev['name']} - {status_color} {ev['status'].upper()} "
                f"({ev['registration_count']} registrations)"
            ):
                col1, col2, col3 = st.columns(3)
                with col1:
                    st.write(f"**ID:** `{ev['id']}`")
                    st.write(f"**Type:** {ev['event_type']}")
                    st.write(f"**Status:** {ev['status']}")
                with col2:
                    st.write(f"**Organizer:** {ev['organizer_id']}")
                    st.write(f"**Registrations:** {ev['registration_count']}")
                    if ev.get("max_registrations"):
                        st.write(f"**Max:** {ev['max_registrations']}")
                with col3:
                    st.write(f"**Created:** {ev['created_at'][:10]}")
                    if ev.get("description"):
                        st.write(f"**Description:** {ev['description']}")

                # Status update
                new_status = st.selectbox(
                    "Change status",
                    ["active", "draft", "ended", "archived"],
                    index=["active", "draft", "ended", "archived"].index(ev["status"]),
                    key=f"status_{ev['id']}"
                )
                if st.button("Update Status", key=f"update_{ev['id']}"):
                    r = requests.patch(
                        f"{API_BASE}/events/{ev['id']}",
                        json={"status": new_status},
                        timeout=5
                    )
                    if r.status_code == 200:
                        st.success("Status updated")
                        st.rerun()
                    else:
                        st.error(f"Update failed: {r.text}")


# ── Create event ──────────────────────────────────────────────────────────────
with tab_create:
    st.subheader("Create New Event")

    with st.form("create_event_form"):
        name         = st.text_input("Event name *", placeholder="TechSummit 2026")
        description  = st.text_area("Description", placeholder="Annual technology conference")
        event_type   = st.selectbox(
            "Event type *",
            ["professional", "public"],
            help="Professional → LinkedIn profile sent. Public → public profile sent."
        )
        organizer_id = st.text_input("Organizer ID *", placeholder="ORG001")
        location     = st.text_input("Location", placeholder="Austin Convention Center")

        col1, col2 = st.columns(2)
        with col1:
            starts_at = st.date_input("Start date")
        with col2:
            ends_at = st.date_input("End date")

        max_reg = st.number_input(
            "Max registrations (0 = unlimited)",
            min_value=0, value=0
        )
        status = st.selectbox("Initial status", ["draft", "active"])

        submitted = st.form_submit_button("Create Event", use_container_width=True)

        if submitted:
            if not name or not organizer_id:
                st.error("Event name and Organizer ID are required")
            else:
                payload = {
                    "name":         name,
                    "description":  description,
                    "event_type":   event_type,
                    "organizer_id": organizer_id,
                    "location":     location or None,
                    "status":       status,
                    "starts_at":    starts_at.isoformat() if starts_at else None,
                    "ends_at":      ends_at.isoformat() if ends_at else None,
                    "max_registrations": max_reg if max_reg > 0 else None,
                }
                try:
                    r = requests.post(
                        f"{API_BASE}/events/",
                        json=payload,
                        timeout=5
                    )
                    if r.status_code == 201:
                        ev = r.json()
                        st.success(f"✅ Event created: **{ev['name']}**")
                        st.code(ev["id"], language=None)
                        st.info("Copy this Event ID - you need it to create a beacon signal.")
                    else:
                        st.error(f"Failed: {r.text}")
                except Exception as e:
                    st.error(f"Error: {e}")
