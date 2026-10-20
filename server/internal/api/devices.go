package api

import "net/http"

// Devices is GET /Lumiere/Devices: this account's sign-ins.
func (h AuthHandler) Devices(w http.ResponseWriter, r *http.Request) {
	sess, ok := SessionFrom(r.Context())
	if !ok {
		unauthorized(w)
		return
	}
	list, err := h.Store.SignedInDevices(sess.AccountID, sess.Token)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"lookup failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"Devices": list})
}

// SignOutDevice is DELETE /Lumiere/Devices/{id}: that device is signed out
// at once, as a lost phone should be.
func (h AuthHandler) SignOutDevice(w http.ResponseWriter, r *http.Request) {
	sess, ok := SessionFrom(r.Context())
	if !ok {
		unauthorized(w)
		return
	}
	done, err := h.Store.SignOutDevice(sess.AccountID, r.PathValue("id"))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not sign out"})
		return
	}
	if !done {
		writeJSON(w, http.StatusNotFound, errorBody{"no such device"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
