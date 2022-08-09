#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>

int main(int argc, char* argv[])
{
	struct input_event ev[64];
	int fevdev = -1;
	int result = 0;
	int size = sizeof(struct input_event);
	int rd;
	int value;
	char name[256] = "Unknown";
	char device[256];

	strncpy(device, argv[1], sizeof(device));

	fevdev = open(device, O_RDONLY);
	if (fevdev == -1) {
		fprintf(stderr, "Failed to open event device.\n");
		exit(1);
	}

	result = ioctl(fevdev, EVIOCGNAME(sizeof(name)), name);
	fprintf (stderr, "Reading From : %s (%s)\n", device, name);

	fprintf(stderr, "Getting exclusive access: ");
	result = ioctl(fevdev, EVIOCGRAB, 1);
	fprintf(stderr, "%s\n", (result == 0) ? "SUCCESS" : "FAILURE");

	while (1)
	{
		if ((rd = read(fevdev, ev, size * 64)) < size) {
			break;
		}

		value = ev[0].value;

		if (value != ' ' && ev[1].value == 1 && ev[1].type == 1) {
			int ch = 0;
			switch(ev[1].code) {
				case KEY_0: ch = '0'; break;
				case KEY_1: ch = '1'; break;
				case KEY_2: ch = '2'; break;
				case KEY_3: ch = '3'; break;
				case KEY_4: ch = '4'; break;
				case KEY_5: ch = '5'; break;
				case KEY_6: ch = '6'; break;
				case KEY_7: ch = '7'; break;
				case KEY_8: ch = '8'; break;
				case KEY_9: ch = '9'; break;
				case KEY_ENTER: ch = '\n'; break;
				default: ch = 0; break;
			}
			putc(ch, stdout);
			if (ch == '\n')
				fflush(stdout);
		}
	}

	fprintf(stderr, "Exiting.\n");
	result = ioctl(fevdev, EVIOCGRAB, 1);
	close(fevdev);
	return 0;
}
