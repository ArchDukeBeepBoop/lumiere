package api

import (
	"net/http"

	"lumiere-server/internal/store"
)

// signIn issues a token for an account and answers as a sign-in does.
// Shared by the password path and the first-run account.
func (h AuthHandler) signIn(w http.ResponseWriter, r *http.Request, account store.Account) {
	token, err := randomHex32()
	if err != nil {
		h.Log.Error("cannot mint a token", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"token"})
		return
	}
	creds := CredentialsFrom(r.Header)
	if err := h.Store.IssueToken(token, account.ID, store.SessionInfo{
		Client: creds.Client, Device: creds.Device,
		DeviceID: creds.DeviceID, Version: creds.Version,
	}); err != nil {
		h.Log.Error("cannot store the token", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"token"})
		return
	}

	h.Log.Info("signed in", "user", account.Username,
		"client", creds.Client, "device", creds.Device)

	writeJSON(w, http.StatusOK, AuthenticationResult{
		User: UserDto{
			Id: account.ID, Name: account.Username,
			ServerId: h.Identity.ServerID,
			// True because a password was in fact required and checked. Lumiere
			// decodes this and ignores it, but a client that branches on it would
			// otherwise be told this server is passwordless.
			HasPassword:           true,
			HasConfiguredPassword: true,
		},
		AccessToken: token,
		ServerId:    h.Identity.ServerID,
	})
}
