BIN     := macaskpass
PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
RELEASE := .build/release/$(BIN)

.PHONY: all build install uninstall clean status test

all: build

build:
	swift build -c release
	@echo "构建完成：$(RELEASE)"

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
