"""Signtone Dashboard - Signals page."""

import requests
import streamlit as st

API_BASE = "http://localhost:8000"

st.set_page_config(page_title="Signals - Signtone", page_icon="📡", layout="wide")
st.title("📡 Beacon Signals")
st.markdown("---")

tab_list, tab_create, tab_chime = st.tabs(["All Signals", "Create Signal", "🎵 Chime Preview"])


# ─────────────────────────────────────────────────────────────────────────────
# Tab 1 - List signals
# ─────────────────────────────────────────────────────────────────────────────
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
            status_icon  = "🟢" if sig["status"] == "active" else "🔴"
            profile_icon = "🔇" if sig.get("frequency_profile") == "ultrasonic" else "🔊"
            chime_label  = sig.get("chime_style", "none").capitalize()

            with st.expander(
                f"{status_icon} {profile_icon} {sig['beacon_payload']} - {chime_label} chime"
            ):
                col1, col2 = st.columns(2)
                with col1:
                    st.write(f"**Signal ID:** `{sig['id']}`")
                    st.write(f"**Payload:** `{sig['beacon_payload']}`")
                    st.write(f"**Event ID:** `{sig['event_id']}`")
                with col2:
                    st.write(f"**Frequency:** `{sig.get('frequency_profile', 'ultrasonic')}`")
                    st.write(f"**Chime:** `{sig.get('chime_style', 'none')}`")
                    st.write(f"**Status:** {sig['status']}")
                    st.write(f"**Created:** {sig['created_at'][:10]}")

                # Download WAV
                st.markdown("#### Download Beacon .wav")
                freq = sig.get("frequency_profile", "ultrasonic")
                chime = sig.get("chime_style", "none")
                if freq == "ultrasonic":
                    st.info("🔇 Ultrasonic - inaudible to humans, ~30m range")
                else:
                    st.info("🔊 Audible - pleasant tone, ~300m range")

                wav_url = f"{API_BASE}/signals/{sig['id']}/wav"
                try:
                    wav_resp = requests.get(wav_url, timeout=10)
                    if wav_resp.status_code == 200:
                        st.download_button(
                            label       = f"⬇️ Download {sig['beacon_payload']}.wav",
                            data        = wav_resp.content,
                            file_name   = f"signtone_{sig['beacon_payload']}_{freq}.wav",
                            mime        = "audio/wav",
                            key         = f"wav_{sig['id']}",
                            use_container_width=True,
                        )
                    else:
                        st.error("Failed to generate .wav")
                except Exception as e:
                    st.error(f"Error: {e}")

                # Deactivate / Delete
                col_deact, col_del = st.columns(2)
                with col_deact:
                    if sig["status"] == "active":
                        if st.button("⏸ Deactivate", key=f"deact_{sig['id']}",
                                     use_container_width=True):
                            r = requests.patch(
                                f"{API_BASE}/signals/{sig['id']}",
                                json={"status": "inactive"}, timeout=5)
                            if r.status_code == 200:
                                st.success("Deactivated")
                                st.rerun()

                with col_del:
                    confirm_key = f"confirm_del_{sig['id']}"
                    if confirm_key not in st.session_state:
                        st.session_state[confirm_key] = False

                    if not st.session_state[confirm_key]:
                        if st.button("🗑 Delete", key=f"del_{sig['id']}",
                                     use_container_width=True):
                            st.session_state[confirm_key] = True
                            st.rerun()
                    else:
                        st.warning("Are you sure?")
                        c1, c2 = st.columns(2)
                        with c1:
                            if st.button("✅ Yes", key=f"yes_{sig['id']}",
                                         use_container_width=True):
                                r = requests.delete(
                                    f"{API_BASE}/signals/{sig['id']}", timeout=5)
                                if r.status_code in (200, 204):
                                    st.success("Deleted")
                                    st.session_state[confirm_key] = False
                                    st.rerun()
                        with c2:
                            if st.button("❌ Cancel", key=f"no_{sig['id']}",
                                         use_container_width=True):
                                st.session_state[confirm_key] = False
                                st.rerun()


# ─────────────────────────────────────────────────────────────────────────────
# Tab 2 - Create signal
# ─────────────────────────────────────────────────────────────────────────────
with tab_create:
    st.subheader("Create New Beacon Signal")

    # ── Frequency profile explainer ───────────────────────────────────────────
    col_u, col_a = st.columns(2)
    with col_u:
        st.info(
            "**🔇 Ultrasonic (15-17 kHz)**\n\n"
            "- Inaudible to most humans\n"
            "- Best for quiet/small venues\n"
            "- Range: ~20-40m indoors"
        )
    with col_a:
        st.success(
            "**🔊 Audible (4-6 kHz)**\n\n"
            "- Pleasant tone, sounds intentional\n"
            "- Best for large venues & outdoors\n"
            "- Range: ~150-300m"
        )

    st.markdown("---")

    # Load events
    try:
        events_resp = requests.get(
            f"{API_BASE}/events/", params={"status": "active"}, timeout=5)
        events = events_resp.json() if events_resp.status_code == 200 else []
    except Exception:
        events = []

    if "created_signal" not in st.session_state:
        st.session_state.created_signal = None
    if "created_wav" not in st.session_state:
        st.session_state.created_wav = None

    with st.form("create_signal_form"):
        # Event picker
        if events:
            event_options = {
                f"{ev['name']} ({ev['event_type']})": ev["id"] for ev in events
            }
            selected_event = st.selectbox("Select event *", list(event_options.keys()))
            event_id = event_options[selected_event]
        else:
            st.warning("No active events. Create an event first.")
            event_id = st.text_input("Or enter Event ID manually")

        beacon_payload = st.text_input(
            "Beacon payload *",
            placeholder="CONF2026",
            max_chars=32,
            help="Short unique ASCII code - gets encoded into the audio beacon.",
        )

        description = st.text_input(
            "Description", placeholder="Main stage check-in beacon")

        st.markdown("#### Signal Options")
        col_freq, col_chime = st.columns(2)

        with col_freq:
            frequency_profile = st.radio(
                "Frequency profile",
                options=["ultrasonic", "audible"],
                format_func=lambda x: (
                    "🔇 Ultrasonic (15-17 kHz) - inaudible, small venues"
                    if x == "ultrasonic"
                    else "🔊 Audible (4-6 kHz) - pleasant tone, large venues"
                ),
                help="Audible travels much further but people will hear it.",
            )

        with col_chime:
            chime_style = st.radio(
                "Chime style",
                options=["none", "marimba", "bell", "modern"],
                format_func=lambda x: {
                    "none":    "🔕 None - raw BFSK only",
                    "marimba": "🪘 Marimba - warm, wooden",
                    "bell":    "🔔 Bell - clear, premium",
                    "modern":  "✨ Modern - tech ding",
                }.get(x, x),
                help="Chime plays before/after the BFSK data. Preview in the Chime tab.",
            )

        submitted = st.form_submit_button(
            "Create Signal + Generate .wav", use_container_width=True)

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
                            "event_id":          event_id,
                            "beacon_payload":    beacon_payload.upper(),
                            "description":       description or None,
                            "frequency_profile": frequency_profile,
                            "chime_style":       chime_style,
                        },
                        timeout=5,
                    )
                    if r.status_code == 201:
                        sig = r.json()
                        st.success(f"✅ Signal created: **{sig['beacon_payload']}**")
                        wav_url  = f"{API_BASE}/signals/{sig['id']}/wav"
                        wav_resp = requests.get(wav_url, timeout=10)
                        if wav_resp.status_code == 200:
                            st.session_state.created_signal = sig
                            st.session_state.created_wav    = wav_resp.content
                        else:
                            st.error("Signal created but .wav generation failed.")
                    elif r.status_code == 409:
                        st.error(
                            f"Payload '{beacon_payload.upper()}' already in use.")
                    else:
                        st.error(f"Failed: {r.text}")
                except Exception as e:
                    st.error(f"Error: {e}")

    # Download outside form
    if st.session_state.created_signal and st.session_state.created_wav:
        sig = st.session_state.created_signal
        freq  = sig.get("frequency_profile", "ultrasonic")
        chime = sig.get("chime_style", "none")
        st.success(f"✅ Ready: **{sig['beacon_payload']}** | {freq} | {chime} chime")
        st.download_button(
            label     = f"⬇️ Download {sig['beacon_payload']}.wav",
            data      = st.session_state.created_wav,
            file_name = f"signtone_{sig['beacon_payload']}_{freq}.wav",
            mime      = "audio/wav",
            use_container_width=True,
        )
        if st.button("Create another signal"):
            st.session_state.created_signal = None
            st.session_state.created_wav    = None
            st.rerun()


# ─────────────────────────────────────────────────────────────────────────────
# Tab 3 - Chime preview
# ─────────────────────────────────────────────────────────────────────────────
with tab_chime:
    st.subheader("🎵 Chime Sound Preview")
    st.write(
        "Listen to each chime style before choosing one for your event. "
        "The chime plays before and after the BFSK data beacon."
    )
    st.markdown("---")

    chimes = [
        ("marimba", "🪘 Marimba",
         "Warm wooden tones - C5→E5→G5. Friendly and approachable. "
         "Great for conferences and community events."),
        ("bell",    "🔔 Bell",
         "Clear bell strikes - C6→G6 with decay tail. Premium feel. "
         "Great for hotel events, galas, and upscale venues."),
        ("modern",  "✨ Modern",
         "Two-tone synthetic ding - A5→E6. Clean and tech-forward. "
         "Great for product launches, hackathons, and tech events."),
    ]

    for style, label, description in chimes:
        with st.container():
            c1, c2 = st.columns([2, 1])
            with c1:
                st.markdown(f"### {label}")
                st.write(description)
            with c2:
                try:
                    wav_resp = requests.get(
                        f"{API_BASE}/signals/chime/{style}/wav", timeout=5)
                    if wav_resp.status_code == 200:
                        st.audio(wav_resp.content, format="audio/wav")
                        st.download_button(
                            label     = f"⬇️ Download {style} chime",
                            data      = wav_resp.content,
                            file_name = f"signtone_chime_{style}.wav",
                            mime      = "audio/wav",
                            key       = f"dl_chime_{style}",
                        )
                    else:
                        st.error(f"Failed to load {style} chime")
                except Exception as e:
                    st.error(f"Error: {e}")

            st.markdown("---")
