package hcore

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/hiddify/hiddify-core/v2/config"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

// ParseOutbounds reads a subscription config file (or raw content) and returns
// the list of outbound nodes without starting sing-box.  This allows the
// Flutter UI to display the node list before the user connects.
func (s *CoreService) ParseOutbounds(ctx context.Context, in *ParseOutboundsRequest) (*OutboundGroupList, error) {
	return ParseOutbounds(in)
}

func ParseOutbounds(in *ParseOutboundsRequest) (*OutboundGroupList, error) {
	defer config.DeferPanicToError("parseOutbounds", func(err error) {
		Log(LogLevel_FATAL, LogType_CONFIG, err.Error())
	})

	content := in.ConfigContent
	if content == "" && in.ConfigPath != "" {
		data, err := os.ReadFile(in.ConfigPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read config: %w", err)
		}
		content = string(data)
	}
	if content == "" {
		return &OutboundGroupList{}, nil
	}

	// Use the existing parser to convert any format (v2ray / clash / sing-box)
	// into sing-box options.  We pass nil for HiddifyOptions so it uses defaults.
	opts, err := config.ParseConfigContentToOptions(content, false, config.DefaultHiddifyOptions(), false)
	if err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	// Extract user-facing outbounds (skip internal ones like dns-out, direct, block, etc.)
	var items []*OutboundInfo
	for _, out := range opts.Outbounds {
		if isInternalOutbound(out) {
			continue
		}
		info := outboundToInfo(out)
		if info != nil {
			items = append(items, info)
		}
	}

	// Wrap in a single OutboundGroup (matching the live data structure)
	group := &OutboundGroup{
		Tag:        "select",
		Type:       C.TypeSelector,
		Selectable: true,
		Items:      items,
	}

	return &OutboundGroupList{
		Items: []*OutboundGroup{group},
	}, nil
}

// isInternalOutbound returns true for outbounds that are infrastructure
// (dns, direct, block, bypass, etc.) and should not be shown to the user.
func isInternalOutbound(out option.Outbound) bool {
	switch out.Type {
	case C.TypeDNS, C.TypeDirect, C.TypeBlock:
		return true
	}
	tag := out.Tag
	if strings.Contains(tag, "§hide§") {
		return true
	}
	for _, predefined := range config.PredefinedOutboundTags {
		if tag == predefined {
			return true
		}
	}
	return false
}

// outboundToInfo converts a sing-box option.Outbound to a protobuf OutboundInfo.
func outboundToInfo(out option.Outbound) *OutboundInfo {
	info := &OutboundInfo{
		Tag:        out.Tag,
		TagDisplay: TrimTagName(out.Tag),
		Type:       out.Type,
		IsVisible:  true,
	}

	// Extract host/port from the outbound options where available.
	switch out.Type {
	case C.TypeVMess:
		info.Host = out.VMessOptions.Server
		info.Port = uint32(out.VMessOptions.ServerPort)
		info.IsSecure = out.VMessOptions.TLS != nil && out.VMessOptions.TLS.Enabled
	case C.TypeVLESS:
		info.Host = out.VLESSOptions.Server
		info.Port = uint32(out.VLESSOptions.ServerPort)
		info.IsSecure = out.VLESSOptions.TLS != nil && out.VLESSOptions.TLS.Enabled
	case C.TypeTrojan:
		info.Host = out.TrojanOptions.Server
		info.Port = uint32(out.TrojanOptions.ServerPort)
		info.IsSecure = true
	case C.TypeShadowsocks:
		info.Host = out.ShadowsocksOptions.Server
		info.Port = uint32(out.ShadowsocksOptions.ServerPort)
	case C.TypeHysteria2:
		info.Host = out.Hysteria2Options.Server
		info.Port = uint32(out.Hysteria2Options.ServerPort)
		info.IsSecure = true
	case C.TypeHysteria:
		info.Host = out.HysteriaOptions.Server
		info.Port = uint32(out.HysteriaOptions.ServerPort)
		info.IsSecure = true
	case C.TypeWireGuard:
		info.Host = out.WireGuardOptions.Server
		info.Port = uint32(out.WireGuardOptions.ServerPort)
		info.IsSecure = true
	case C.TypeTUIC:
		info.Host = out.TUICOptions.Server
		info.Port = uint32(out.TUICOptions.ServerPort)
		info.IsSecure = true
	case C.TypeSSH:
		info.Host = out.SSHOptions.Server
		info.Port = uint32(out.SSHOptions.ServerPort)
	case C.TypeHTTP:
		info.Host = out.HTTPOptions.Server
		info.Port = uint32(out.HTTPOptions.ServerPort)
	case C.TypeSOCKS:
		info.Host = out.SOCKSOptions.Server
		info.Port = uint32(out.SOCKSOptions.ServerPort)
	case C.TypeSelector, C.TypeURLTest:
		info.IsGroup = true
	}

	// Try to resolve country from the tag name (best-effort).
	info.Ipinfo = resolveIpInfoFromTag(out.Tag, info.Host)

	return info
}

// resolveIpInfoFromTag does a best-effort extraction of country info from the
// node tag name.  This is not accurate but gives a reasonable default for the
// flag icon before a real IP lookup.
func resolveIpInfoFromTag(tag string, host string) *IpInfo {
	ipinfo := &IpInfo{}

	// Common country code patterns in node names
	ccMap := map[string]string{
		"🇺🇸": "us", "🇭🇰": "hk", "🇯🇵": "jp", "🇸🇬": "sg", "🇹🇼": "tw",
		"🇰🇷": "kr", "🇬🇧": "gb", "🇩🇪": "de", "🇫🇷": "fr", "🇦🇺": "au",
		"🇨🇦": "ca", "🇳🇱": "nl", "🇮🇳": "in", "🇧🇷": "br", "🇹🇷": "tr",
		"🇷🇺": "ru", "🇦🇷": "ar", "🇮🇪": "ie", "🇦🇪": "ae",
	}
	cnMap := map[string]string{
		"美国": "us", "香港": "hk", "日本": "jp", "新加坡": "sg", "台湾": "tw",
		"韩国": "kr", "英国": "gb", "德国": "de", "法国": "fr", "澳大利亚": "au",
		"加拿大": "ca", "荷兰": "nl", "印度": "in", "巴西": "br", "土耳其": "tr",
		"俄罗斯": "ru", "阿根廷": "ar", "爱尔兰": "ie", "阿联酋": "ae", "澳门": "mo",
	}

	lower := strings.ToLower(tag)
	for emoji, cc := range ccMap {
		if strings.Contains(tag, emoji) {
			ipinfo.CountryCode = cc
			return ipinfo
		}
	}
	for cn, cc := range cnMap {
		if strings.Contains(tag, cn) {
			ipinfo.CountryCode = cc
			return ipinfo
		}
	}

	// Try common 2-letter codes in the tag
	enMap := map[string]string{
		"us": "us", "hk": "hk", "jp": "jp", "sg": "sg", "tw": "tw",
		"kr": "kr", "uk": "gb", "de": "de", "fr": "fr", "au": "au",
	}
	for name, cc := range enMap {
		if strings.Contains(lower, name) {
			ipinfo.CountryCode = cc
			return ipinfo
		}
	}

	return ipinfo
}

// marshalOutboundGroupList is a helper for JSON serialization (unused but
// handy for debugging).
func marshalOutboundGroupList(list *OutboundGroupList) (string, error) {
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}
