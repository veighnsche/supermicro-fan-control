# Contributing to Supermicro Fan Control

Thank you for your interest in contributing! 🎉

## How to Contribute

### Reporting Issues

When reporting issues, please include:
- **Hardware:** Exact Supermicro board model
- **BMC Firmware:** Version (`ipmitool mc info`)
- **OS:** Distribution and kernel version
- **Logs:** Recent output from `journalctl -u fan-control.service -n 100`
- **Symptoms:** Describe what's happening vs what you expected
- **Fan speeds:** Output of `ipmitool sensor | grep FAN`

### Tested Configurations

If you've tested this on different hardware, please submit:
- Board model
- BMC firmware version
- Optimal polling interval
- Temperature curves that work well
- Any modifications needed

Create an issue with "Tested on: [BOARD MODEL]" to share your configuration.

### Code Contributions

1. **Fork the repository**
2. **Create a feature branch:** `git checkout -b feature/my-improvement`
3. **Make your changes**
4. **Test thoroughly** on real hardware
5. **Commit with clear messages**
6. **Submit a pull request**

### Code Style

- Use bash best practices
- Add comments for complex logic
- Keep functions small and focused
- Test error handling paths
- Update README.md if adding features

### Testing Checklist

Before submitting, verify:
- [ ] Script starts without errors
- [ ] Fans respond to temperature changes
- [ ] No IPMI errors in logs
- [ ] Service restarts on failure
- [ ] Cleanup handler restores automatic mode
- [ ] Works after reboot

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
