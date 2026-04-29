package hcore

import (
	"context"
	"runtime"
	"time"

	"github.com/hiddify/hiddify-core/v2/config"
	"github.com/sagernet/sing-box/log"
)

func (s *CoreService) Restart(ctx context.Context, in *StartRequest) (*CoreInfoResponse, error) {
	return Restart(in)
}

func Restart(in *StartRequest) (coreResponse *CoreInfoResponse, err error) {
	defer config.DeferPanicToError("startmobile", func(recovered_err error) {
		coreResponse, err = errorWrapper(MessageType_UNEXPECTED_ERROR, recovered_err)
	})
	log.Debug("[Service] Restarting")
	// if static.CoreState != CoreStates_STARTED {
	// 	return errorWrapper(MessageType_INSTANCE_NOT_STARTED, fmt.Errorf("instance not started"))
	// }
	// if static.Box == nil {
	// 	return errorWrapper(MessageType_INSTANCE_NOT_FOUND, fmt.Errorf("instance not found"))
	// }

	resp, err := Stop()
	if err != nil {
		return resp, err
	}

	// Wait for the OS to fully release the TUN interface after closing.
	// On Android, the kernel needs time to tear down routes and netfilter
	// rules associated with the previous TUN device. Without this delay,
	// openTun() will fail with "permission denied" because the old TUN
	// fd hasn't been fully reclaimed yet.
	if runtime.GOOS == "android" {
		log.Debug("[Service] Waiting for TUN interface release before restart")
		time.Sleep(1500 * time.Millisecond)
	} else {
		time.Sleep(500 * time.Millisecond)
	}

	resp, gErr := StartService(in)
	return resp, gErr
}
