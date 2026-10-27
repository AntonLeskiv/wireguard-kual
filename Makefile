BUILD_DIR := build
EXT_BIN_DIR := wireguard/bin

.PHONY: all clean wireguard-go wg package

all: wireguard-go wg package

wireguard-go:
	mkdir -p $(BUILD_DIR)
	@if [ ! -d "$(BUILD_DIR)/wireguard-go" ]; then \
		git clone --depth 1 https://git.zx2c4.com/wireguard-go $(BUILD_DIR)/wireguard-go; \
	fi
	cd $(BUILD_DIR)/wireguard-go && \
	GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
	go build -trimpath -ldflags="-s -w -extldflags=-static" -o ../../$(EXT_BIN_DIR)/wireguard-go

wg:
	mkdir -p $(BUILD_DIR)
	@if [ ! -d "$(BUILD_DIR)/wireguard-tools" ]; then \
		git clone --depth 1 https://git.zx2c4.com/wireguard-tools $(BUILD_DIR)/wireguard-tools; \
	fi
	$(MAKE) -C $(BUILD_DIR)/wireguard-tools/src CC=arm-linux-gnueabihf-gcc LDFLAGS="-static" WITH_BASHCOMPLETION=no WITH_WGQUICK=no WITH_SYSTEMDUNITS=no
	arm-linux-gnueabihf-strip -s $(BUILD_DIR)/wireguard-tools/src/wg
	cp $(BUILD_DIR)/wireguard-tools/src/wg $(EXT_BIN_DIR)/wg

package:
	chmod +x $(EXT_BIN_DIR)/wg-control.sh
	zip -r kindle-wireguard-kual.zip wireguard/ -x "*/.gitkeep"

clean:
	rm -rf $(BUILD_DIR) $(EXT_BIN_DIR)/wireguard-go $(EXT_BIN_DIR)/wg kindle-wireguard-kual.zip
