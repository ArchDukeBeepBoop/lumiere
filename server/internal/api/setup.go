package api

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"

	"lumiere-server/internal/store"
)

// The first run. A new server has no account and no library; these two
// unauthenticated endpoints let the apps' guide make the first account, and
// nothing else — once an account exists, the account call refuses.

// SetupState is GET /Lumiere/Setup.
type SetupState struct {
	NeedsAccount bool   `json:"NeedsAccount"`
	ServerName   string `json:"ServerName"`
}

// Setup answers whether this server still needs its first account.
func (h AuthHandler) Setup(w http.ResponseWriter, r *http.Request) {
	any, err := h.Store.AnyAccount()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"lookup failed"})
		return
	}
	writeJSON(w, http.StatusOK, SetupState{NeedsAccount: !any, ServerName: h.Identity.ServerName})
}

// CreateAccount is POST /Lumiere/Setup/Account {"Username", "Password"}: the
// first account, answered as a sign-in so the app is signed in at once.
func (h AuthHandler) CreateAccount(w http.ResponseWriter, r *http.Request) {
	// Only from the Mac the server runs on. Unauthenticated by necessity, so
	// with sharing on, anyone on the Wi-Fi could otherwise claim a new server
	// before its owner did.
	if !fromLoopback(r) {
		writeJSON(w, http.StatusForbidden, errorBody{"make the first account in Lumiere on the Mac that runs the server"})
		return
	}
	var req struct{ Username, Password string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"invalid request body"})
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || len(req.Password) < minPasswordLength {
		writeJSON(w, http.StatusBadRequest, errorBody{"choose a name and a password of at least 8 characters"})
		return
	}
	hash, err := hashPassword(req.Password)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not hash"})
		return
	}
	id, err := randomHex32()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"id"})
		return
	}
	err = h.Store.CreateFirstAccount(id, req.Username, hash)
	if errors.Is(err, store.ErrAccountsExist) {
		writeJSON(w, http.StatusConflict, errorBody{"this server already has an account; sign in instead"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
		return
	}
	h.Log.Info("first account created", "user", req.Username)
	h.signIn(w, r, store.Account{ID: id, Username: req.Username, PasswordHash: hash})
}

// ChangePassword is POST /Lumiere/Account/Password {"Current", "New"}.
func (h AuthHandler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	sess, ok := SessionFrom(r.Context())
	if !ok {
		unauthorized(w)
		return
	}
	var req struct{ Current, New string }
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil || len(req.New) < minPasswordLength {
		writeJSON(w, http.StatusBadRequest, errorBody{"a new password of at least 8 characters"})
		return
	}
	account, err := h.Store.AccountByID(sess.AccountID)
	if err == nil && h.Throttle != nil && refuseThrottled(w, h.Throttle.Blocked(r, account.Username)) {
		return
	}
	if err != nil || !verifyPassword(account.PasswordHash, req.Current) {
		if err == nil && h.Throttle != nil {
			h.Throttle.Failed(r, account.Username)
		}
		writeJSON(w, http.StatusForbidden, errorBody{"the current password is wrong"})
		return
	}
	hash, err := hashPassword(req.New)
	if err == nil {
		err = h.Store.SetPasswordHash(account.ID, hash)
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func fromLoopback(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
