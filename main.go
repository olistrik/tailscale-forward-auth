// This code is forked from Tailscale codebase which is governed by
// a BSD-style licence. See https://github.com/tailscale/tailscale
//
// The link below is the code from which this code originates:
// https://github.com/tailscale/tailscale/blob/741ae9956e674177687062b5499a80db83505076/cmd/nginx-auth/nginx-auth.go

package main

import (
	"flag"
	"log"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/coreos/go-systemd/activation"
	"tailscale.com/client/local"
	"tailscale.com/tailcfg"
)

var (
	tcpAddr                  = flag.String("addr", "", "the address to listen on, for example 127.0.0.1:")
	sockPath                 = flag.String("sockpath", "", "the filesystem path for the unix socket this service exposes")
	headerRemoteIP           = flag.String("remote-ip-header", "X-Forwarded-For", "HTTP header field containing the remote IP")
	headerRemotePort         = flag.String("remote-port-header", "X-Forwarded-Port", "HTTP header field containing the remote port")
	headerPermitPrivate      = flag.String("permit-private-header", "X-Permit-Private", "HTTP header field to permit private network connections without tailscale")
	headerExpectedTailnet    = flag.String("expected-tailnet-header", "X-Expected-Tailnet", "HTTP header field to set expected tailnet")
	headerRequiresCapability = flag.String("requires-capability", "X-Requires-Capability", "HTTP header field to set the required application capability")
	debug                    = flag.Bool("debug", false, "enable debug logging")
)

func ParseBoolish(val string) (bool, error) {
	if val == "" {
		return false, nil
	}

	return strconv.ParseBool(val)
}

func main() {
	flag.Parse()

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		client := &local.Client{}

		if *debug {
			log.Printf("received request with header %+v", r.Header)
		}

		remoteHost := r.Header.Get(*headerRemoteIP)
		if remoteHost == "" {
			w.WriteHeader(http.StatusBadRequest)
			log.Printf("missing header %s", *headerRemoteIP)
			return
		}

		remotePort := r.Header.Get(*headerRemotePort)
		if remotePort == "" {
			w.WriteHeader(http.StatusBadRequest)
			log.Printf("missing header %s", *headerRemotePort)
			return
		}

		remoteAddr, err := netip.ParseAddrPort(net.JoinHostPort(remoteHost, remotePort))
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			log.Printf("remote address and port are not valid: %v", err)
			return
		}

		permitPrivate, err := ParseBoolish(r.Header.Get(*headerPermitPrivate))
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			log.Printf("could not parse boolean header %s", *headerPermitPrivate)
		}

		info, err := client.WhoIs(r.Context(), remoteAddr.String())
		if err != nil {
			if permitPrivate && remoteAddr.Addr().IsPrivate() {
				// respond without additional headers.
				w.WriteHeader(http.StatusNoContent)
				return
			}

			w.WriteHeader(http.StatusUnauthorized)
			log.Printf("can't look up %s: %v", remoteAddr, err)
			return
		}

		if len(info.Node.Tags) != 0 {
			w.WriteHeader(http.StatusForbidden)
			log.Printf("node %s is tagged", info.Node.Hostinfo.Hostname())
			return
		}

		// tailnet of connected node. When accessing shared nodes, this
		// will be empty because the tailnet of the sharee is not exposed.
		var tailnet string

		if !info.Node.Hostinfo.ShareeNode() {
			var ok bool
			_, tailnet, ok = strings.Cut(info.Node.Name, info.Node.ComputedName+".")
			if !ok {
				w.WriteHeader(http.StatusUnauthorized)
				log.Printf("can't extract tailnet name from hostname %q", info.Node.Name)
				return
			}
			tailnet = strings.TrimSuffix(tailnet, ".ts.net")
		}

		expectedTailnet := r.Header.Get(*headerExpectedTailnet)
		if expectedTailnet != "" && expectedTailnet != tailnet {
			w.WriteHeader(http.StatusForbidden)
			log.Printf("node %s is part of tailnet %s, wanted: %s", info.Node.Name, tailnet, url.QueryEscape(expectedTailnet))
			return
		}

		requiredCapability := tailcfg.PeerCapability(r.Header.Get(*headerRequiresCapability))
		if requiredCapability != "" && !info.CapMap.HasCapability(requiredCapability) {
			w.WriteHeader(http.StatusForbidden)
			log.Printf("user %s does not have required capability: %s", info.UserProfile.LoginName, requiredCapability)
			return
		}

		h := w.Header()
		h.Set("Tailscale-Login", strings.Split(info.UserProfile.LoginName, "@")[0])
		h.Set("Tailscale-User", info.UserProfile.LoginName)
		h.Set("Tailscale-Name", info.UserProfile.DisplayName)
		h.Set("Tailscale-Profile-Picture", info.UserProfile.ProfilePicURL)
		h.Set("Tailscale-Tailnet", tailnet)
		w.WriteHeader(http.StatusNoContent)
	})

	listeners, err := activation.Listeners()
	if err != nil {
		// NOTE(Oli): I don't think activation.listeners() errors when no sockets are passed...
		log.Fatalf("no sockets passed to this service with systemd: %v", err)
	}

	if *tcpAddr != "" {
		ln, err := net.Listen("tcp", *tcpAddr)
		if err != nil {
			log.Fatalf("can't listen on %s: %v", *tcpAddr, err)
		}
		defer ln.Close()

		listeners = append(listeners, ln)
	}

	if *sockPath != "" {
		_ = os.Remove(*sockPath) // ignore error, this file may not already exist
		ln, err := net.Listen("unix", *sockPath)
		if err != nil {
			log.Fatalf("can't listen on %s: %v", *sockPath, err)
		}
		defer ln.Close()

		listeners = append(listeners, ln)
	}

	if len(listeners) == 0 {
		log.Fatal("No listeners were passed to systemd or specified using tcpAddr or sockPath.")
	}

	// NOTE(Xe): normally you'd want to make a waitgroup here and then register
	// each listener with it. In this case I want this to blow up horribly if
	// any of the listeners stop working. systemd will restart it due to the
	// socket activation at play.
	//
	// TL;DR: Let it crash, it will come back
	for _, ln := range listeners {
		go func(ln net.Listener) {
			log.Printf("listening on %s", ln.Addr())
			log.Fatal(http.Serve(ln, mux))
		}(ln)
	}

	for {
		select {}
	}
}
