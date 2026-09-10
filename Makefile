BIN     := macaskpass
PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
RELEASE := .build/release/$(BIN)

# 代码签名身份。
#
# 用真实证书签名后，钥匙串条目的 ACL 绑定的是「签名主体 + 标识符」，而不是
# ad-hoc 签名的 cdhash，因此重新编译、重新安装之后都不必再跑一次 --set-password。
# 留空则自动挑第一个可用的 Apple Development / Developer ID 身份；
# 一个都没有就退回 ad-hoc 签名（功能不受影响，只是每次重编都要重存密码）。
CODESIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | \
	awk -F'"' '/Apple Development|Developer ID Application/ {print $$2; exit}')

# 签名标识符必须固定，它是 Designated Requirement 的一部分。
CODESIGN_IDENTIFIER := macaskpass

.PHONY: all build sign install uninstall clean status test identity

all: build

build:
	swift build -c release
	@$(MAKE) --no-print-directory sign

sign:
	@test -x $(RELEASE) || { echo "还没构建，请先运行：make"; exit 1; }
	@if [ -n "$(CODESIGN_ID)" ]; then \
		echo "签名身份：$(CODESIGN_ID)"; \
		codesign -f -s "$(CODESIGN_ID)" -i $(CODESIGN_IDENTIFIER) $(RELEASE) || exit 1; \
		codesign -d -r- $(RELEASE) 2>&1 | grep '^designated' | sed 's/^/  /'; \
	else \
		echo "没找到可用的签名证书，保持 ad-hoc 签名"; \
		echo "  注意：ad-hoc 签名下每次重新编译后都要重跑 macaskpass --set-password"; \
	fi

## 列出可用的签名身份，方便手工指定 CODESIGN_ID=...
identity:
	@security find-identity -v -p codesigning || true
	@echo "当前会用：$(if $(CODESIGN_ID),$(CODESIGN_ID),（无，退回 ad-hoc）)"

## 需要 root：make && sudo make install
install:
	@test -x $(RELEASE) || { echo "还没构建，请先运行：make"; exit 1; }
	install -d $(BINDIR)
	install -m 755 $(RELEASE) $(BINDIR)/$(BIN)
	@codesign --verify --verbose=1 $(BINDIR)/$(BIN) 2>&1 | sed 's/^/  /'
	@echo "已安装：$(BINDIR)/$(BIN)"
	@echo "下一步（不要用 sudo 跑）：$(BINDIR)/$(BIN) --set-password"

uninstall:
	rm -f $(BINDIR)/$(BIN)
	@echo "已删除 $(BINDIR)/$(BIN)（钥匙串里的密码请用 macaskpass --delete 单独清理）"

clean:
	rm -rf .build

status:
	@$(RELEASE) --status

test:
	@$(RELEASE) --test
