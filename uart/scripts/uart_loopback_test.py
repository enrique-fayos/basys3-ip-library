"""Self-checking hardware test for the Basys 3 UART loopback design."""

import sys

try:
    import serial
except ImportError:
    serial = None


BAUD_RATE = 115_200
TIMEOUT_SECONDS = 2.0
TEST_BYTES = bytes([0x00, 0xFF, 0x01, 0x80, 0x96, 0x57, 0xAB])


def format_bytes(data):
    """Return a byte sequence as space-separated hexadecimal values."""
    return " ".join(f"{byte:02X}" for byte in data)


def print_result(received, message):
    """Print the transmitted and received sequences and a failure message."""
    print(f"TX: {format_bytes(TEST_BYTES)}")
    print(f"RX: {format_bytes(received)}")
    print(f"FAIL: {message}")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} SERIAL_PORT", file=sys.stderr)
        print(f"Example: {sys.argv[0]} COM5", file=sys.stderr)
        print(f"Example: {sys.argv[0]} /dev/ttyUSB0", file=sys.stderr)
        return 2

    if serial is None:
        print(
            "ERROR: pyserial is not installed. Install it with: pip install pyserial",
            file=sys.stderr,
        )
        return 2

    port_name = sys.argv[1]
    received = b""

    try:
        with serial.Serial(
            port=port_name,
            baudrate=BAUD_RATE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=TIMEOUT_SECONDS,
            write_timeout=TIMEOUT_SECONDS,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as uart:
            uart.reset_input_buffer()

            bytes_written = uart.write(TEST_BYTES)
            uart.flush()
            if bytes_written != len(TEST_BYTES):
                print_result(
                    received,
                    f"Sent only {bytes_written} of {len(TEST_BYTES)} bytes.",
                )
                return 1

            received = uart.read(len(TEST_BYTES))

    except (serial.SerialException, ValueError, OSError) as error:
        print_result(received, f"Serial error on {port_name}: {error}")
        return 1

    print(f"TX: {format_bytes(TEST_BYTES)}")
    print(f"RX: {format_bytes(received)}")

    if len(received) != len(TEST_BYTES):
        print(
            f"FAIL: Expected {len(TEST_BYTES)} bytes but received "
            f"only {len(received)}."
        )
        return 1

    if received != TEST_BYTES:
        print("FAIL: Received data does not match transmitted data.")
        return 1

    print("PASS: UART loopback data matched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
