package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"lumiere-server/internal/store"
)

// AuthHandler serves the sign-in endpoints of spec §3.
type AuthHandler struct {
	Store    *store.Store
	Identity Identity
	Log      *slog.Logger
}

// authenticateRequest is what Lumiere posts. Two fields, and `Pw` rather than
// `Password` — Jellyfin accepts both and Lumiere sends `Pw`, so both are decoded
// and whichever arrived is used.
type authenticateRequest struct {
	Username string `json:"Username"`
	Pw       string `json:"Pw"`
	Password string `json:"Password"`
}

// AuthenticationResult is the response. All three top-level pieces are
// load-bearing (§3.2): User.Id becomes userId in every later request,
// AccessToken becomes the token, ServerId is stored.
type AuthenticationResult struct {
	User        UserDto `json:"User"`
	AccessToken string  `json:"AccessToken"`
	ServerId    string  `json:"ServerId"`
	SessionInfo any     `json:"SessionInfo"`
}

type UserDto struct {
	Id                        string `json:"Id"`
	Name                      string `json:"Name"`
	ServerId                  string `json:"ServerId"`
	HasPassword               bool   `json:"HasPassword"`
	HasConfiguredPassword     bool   `json:"HasConfiguredPassword"`
	HasConfiguredEasyPassword bool   `json:"HasConfiguredEasyPassword"`
	EnableAutoLogin           bool   `json:"EnableAutoLogin"`
}

// AuthenticateByName is the only sign-in path that has to work.
func (h AuthHandler) AuthenticateByName(w http.ResponseWriter, r *http.Request) {
	var req authenticateRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		// A body that will not decode is a client bug, not a credential failure,
		// and saying 400 rather than 401 is the difference between "fix your
		// request" and "try another password".
		writeJSON(w, http.StatusBadRequest, errorBody{"invalid request body"})
		return
	}
	pw := req.Pw
	if pw == "" {
		pw = req.Password
	}

	account, err := h.Store.AccountByName(req.Username)
	if errors.Is(err, store.ErrNoAccount) {
		// The log distinguishes what the response deliberately does not. A client
		// learning whether the username exists is a small leak; whoever is
		// reading the log needs to know, especially for the case below.
		if any, err := h.Store.AnyAccount(); err == nil && !any {
			h.Log.Warn("sign-in attempted before the first account was made; the apps’ first-run guide makes it")
		} else {
			h.Log.Info("sign-in rejected", "reason", "unknown username")
		}
		unauthorized(w)
		return
	}
	if err != nil {
		h.Log.Error("account lookup failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"lookup failed"})
		return
	}

	if !verifyPassword(account.PasswordHash, pw) {
		h.Log.Info("sign-in rejected", "reason", "password", "user", account.Username)
		unauthorized(w)
		return
	}

	h.signIn(w, r, account)
}

// PublicUsers is the sign-in screen's avatar list. Empty is not a degraded
// answer — the live Jellyfin instance returns exactly this (§3.4).
func (h AuthHandler) PublicUsers(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, []UserDto{})
}

// QuickConnectEnabled returns the literal false, disabling the whole flow.
//
// A 404 would also work — Lumiere reads that as false — but answering honestly
// costs one line and means the client never has to interpret a missing endpoint.
func (h AuthHandler) QuickConnectEnabled(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, false)
}

// CurrentUser answers /Users/Me, which clients use to confirm a stored token is
// still good. Reached only through RequireAuth, so arriving here means it is.
func (h AuthHandler) CurrentUser(w http.ResponseWriter, r *http.Request) {
	sess, ok := SessionFrom(r.Context())
	if !ok {
		unauthorized(w)
		return
	}
	account, err := h.Store.AccountByID(sess.AccountID)
	if err != nil {
		unauthorized(w)
		return
	}
	writeJSON(w, http.StatusOK, UserDto{
		Id: account.ID, Name: account.Username, ServerId: h.Identity.ServerID,
		HasPassword: true, HasConfiguredPassword: true,
	})
}

type errorBody struct {
	Message string `json:"Message"`
}

// unauthorized is the single shape of a rejected credential.
//
// 401 for every reason, with no detail: the spec says Lumiere turns any 401 or
// 403 into "signed out" without reading the body, so the body exists only for a
// human with curl.
func unauthorized(w http.ResponseWriter) {
	writeJSON(w, http.StatusUnauthorized, errorBody{"invalid username or password"})
}
