# ppnode-tools

A safe and predictable lifecycle manager for **PPanel-node (ppnode)**.

This tool is designed to manage **multiple ppnode instances** on a single server
using **systemd**, based on an existing or officially installed ppnode setup.

---

## ✨ Features

- Official ppnode installer wrapper (optional)
- systemd-based multi-instance management
- Fully isolated config directories per instance
- Interactive TUI manager
- No magic, no background behavior
- Designed for production use

---

## ❗ Design Philosophy

This project **does NOT** use `curl | bash`.

Why?

Because:
- ppnode management logic is non-trivial
- partial execution can corrupt installations
- predictable behavior is more important than one-liners

You always install the tool **explicitly**.

---

## 📦 Installation

```bash
curl -fsSL https://raw.githubusercontent.com/echo00023/ppnode-tools/main/ppnode.sh \
  -o /usr/local/bin/ppnode

chmod +x /usr/local/bin/ppnode
