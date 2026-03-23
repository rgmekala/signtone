"""Signtone Dashboard - Signals page."""

import requests
import streamlit as st

API_BASE = "http://localhost:8000"

st.set_page_config(page_title="Signals - Signtone", page_icon="📡", layout="wide")
st.title("📡 Beacon Signals")
st.markdown("---")

tab_list, tab_create = st.tabs(["All Signals", "Create Signal"])

# ── List signals ──────────────────────────────────────────────────────────────
with tab_list:
    st.subheader("Your Beacon Signals")

    try:
        resp    = requests.get(f"{API_BASE}/signals/", timeout=5)
        signals = resp.json() if resp.status_code == 200 else []
    except Exception as e:
        st.error(f"Failed to load signals: {e}")
        signals = []

    if not signals:
        st.info("No signals yet. Create one in the 'Create Signal' tab.")
    else:
        for sig in signals:
            status_icon = "🟢" if sig["status"] == "active" else "🔴"
            with st.expander(
                f"{status_icon} {sig['beacon_payload']} - {sig['status'].upper()}"
            ):
                col1, col2 = st.columns(2)
                with col1:
                    st.write(f"**Signal ID:** `{sig['id']}`")
                    st.write(f"**Beacon payload:** `{sig['beacon_payload']}`")
                    st.write(f"**Event ID:** `{sig['event_id']}`")
                with col2:
                    st.write(f"**Status:** {sig['status']}")
                    st.write(f"**Created:** {sig['created_at'][:10]}")
                    if sig.get("expires_at"):
                        st.write(f"**Expires:** {sig['expires_at'][:10]}")

                # Download .wav button
                st.markdown("#### Download Beacon .wav")
                st.info(
                    "Play this file through your PA system or embed it in "
                    "your radio broadcast. It is inaudible to humans."
                )
                wav_url = f"{API_BASE}/signals/{sig['id']}/wav"
                try:
                    wav_resp = requests.get(wav_url, timeout=10)
                    if wav_resp.status_code == 200:
                        st.download_button(
                            label       = f"⬇️ Download {sig['beacon_payload']}.wav",
                            data        = wav_resp.content,
                            file_name   = f"signtone_{sig['beacon_payload']}.wav",
                            mime        = "audio/wav",
                            key         = f"wav_{sig['id']}",
                            use_container_width=True,
                        )
                    else:
                        st.error("Failed to generate .wav")
                except Exception as e:
                    st.error(f"Error: {e}")

                # Action buttons
                col_deact, col_del = st.columns(2)

                with col_deact:
                    if sig["status"] == "active":
                        if st.button(
                            "⏸ Deactivate",
                            key=f"deact_{sig['id']}",
                            type="secondary",
                            use_container_width=True,
                        ):
                            r = requests.patch(
                                f"{API_BASE}/signals/{sig['id']}",
                                json={"status": "inactive"},
                                timeout=5
                            )
                            if r.status_code == 200:
                                st.success("Signal deactivated")
                                st.rerun()

                with col_del:
                    # Two-click delete: first click sets confirm state
                    confirm_key = f"confirm_del_{sig['id']}"
                    if confirm_key not in st.session_state:
                        st.session_state[confirm_key] = False

                    if not st.session_state[confirm_key]:
                        if st.button(
                            "🗑 Delete",
                            key=f"del_{sig['id']}",
                            type="secondary",
                            use_container_width=True,
                        ):
                            st.session_state[confirm_key] = True
                            st.rerun()
                    else:
                        st.warning("Are you sure?")
                        c1, c2 = st.columns(2)
                        with c1:
                            if st.button(
                                "✅ Yes, delete",
                                key=f"confirm_yes_{sig['id']}",
                                type="primary",
                                use_container_width=True,
                            ):
                                r = requests.delete(
                                    f"{API_BASE}/signals/{sig['id']}",
                                    timeout=5
                                )
                                if r.status_code in (200, 204):
                                    st.success("Signal deleted")
                                    st.session_state[confirm_key] = False
                                    st.rerun()
                                else:
                                    st.error(f"Delete failed: {r.text}")
                        with c2:
                            if st.button(
                                "❌ Cancel",
                                key=f"confirm_no_{sig['id']}",
                                use_container_width=True,
                            ):
                                st.session_state[confirm_key] = False
                                st.rerun()


# ── Create signal ─────────────────────────────────────────────────────────────
with tab_create:
    st.subheader("Create New Beacon Signal")
    st.info(
        "A beacon signal links a short payload string to an event. "
        "The payload is encoded into an ultrasonic .wav file you can play "
        "through any speaker. When the Signtone app hears it, "
        "it shows the user a registration confirmation card."
    )

    # Load events for dropdown
    try:
        events_resp = requests.get(
            f"{API_BASE}/events/",
            params={"status": "active"},
            timeout=5
        )
        events = events_resp.json() if events_resp.status_code == 200 else []
    except Exception:
        events = []

    # Store created signal in session state so download works outside form
    if "created_signal" not in st.session_state:
        st.session_state.created_signal = None
    if "created_wav" not in st.session_state:
        st.session_state.created_wav = None

    with st.form("create_signal_form"):
        if events:
            event_options = {
                f"{ev['name']} ({ev['event_type']})": ev["id"]
                for ev in events
            }
            selected_event = st.selectbox("Select event *", list(event_options.keys()))
            event_id = event_options[selected_event]
        else:
            st.warning("No active events found. Create an event first.")
            event_id = st.text_input("Or enter Event ID manually")

        beacon_payload = st.text_input(
            "Beacon payload *",
            placeholder="CONF2026",
            max_chars=32,
            help="Short unique code - max 32 ASCII characters. "
                 "This gets encoded into the ultrasonic tone."
        )
        description = st.text_input(
            "Description",
            placeholder="Main stage check-in beacon"
        )

        submitted = st.form_submit_button(
            "Create Signal + Generate .wav",
            use_container_width=True
        )

        if submitted:
            if not event_id or not beacon_payload:
                st.error("Event and beacon payload are required")
            elif not beacon_payload.isascii():
                st.error("Beacon payload must be ASCII characters only")
            else:
                try:
                    r = requests.post(
                        f"{API_BASE}/signals/",
                        json={
                            "event_id":       event_id,
                            "beacon_payload": beacon_payload.upper(),
                            "description":    description or None,
                        },
                        timeout=5
                    )
                    if r.status_code == 201:
                        sig = r.json()
                        st.success(f"✅ Signal created: **{sig['beacon_payload']}**")
                        st.code(sig["id"], language=None)

                        # Fetch wav and store in session state
                        wav_url  = f"{API_BASE}/signals/{sig['id']}/wav"
                        wav_resp = requests.get(wav_url, timeout=10)
                        if wav_resp.status_code == 200:
                            st.session_state.created_signal = sig
                            st.session_state.created_wav    = wav_resp.content
                        else:
                            st.error("Signal created but .wav generation failed.")

                    elif r.status_code == 409:
                        st.error(
                            f"Payload '{beacon_payload.upper()}' is already in use. "
                            "Choose a different payload."
                        )
                    else:
                        st.error(f"Failed: {r.text}")
                except Exception as e:
                    st.error(f"Error: {e}")

    # ── Download button OUTSIDE the form ──────────────────────────────────────
    if st.session_state.created_signal and st.session_state.created_wav:
        sig = st.session_state.created_signal
        st.success(f"✅ Ready to download: **{sig['beacon_payload']}.wav**")
        st.download_button(
            label       = f"⬇️ Download {sig['beacon_payload']}.wav",
            data        = st.session_state.created_wav,
            file_name   = f"signtone_{sig['beacon_payload']}.wav",
            mime        = "audio/wav",
            use_container_width=True,
        )
        if st.button("Create another signal"):
            st.session_state.created_signal = None
            st.session_state.created_wav    = None
            st.rerun()
