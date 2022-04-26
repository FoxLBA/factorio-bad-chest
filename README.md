Adds a Blueprint Deployer chest which can be connected to the circuit network to build a self-expanding factory.

Example commands:

![Construction robot = 1](docs/construction-robot_1.jpg)

Deploy blueprint. Construction robot signal can be any value ≥ 1.

---

![Construction robot = 2](docs/construction-robot_2.jpg)

Deploy blueprint from book. Construction robot signal selects which blueprint to use.  If it is greater than the size of the book, the active blueprint is used instead.

---

![Construction robot = 3](docs/nested_navigation.png)

To select blueprint in books (which are also in the books), signals 1 to 5 indicate which slot to use at the corresponding nesting level. (Construction robot signal is considered as the zero layer)

---

![Construction robot = 1](docs/construction-robot_3.jpg)

Deconstruct or upgrade area. W = width, H = height. Supports deconstruction filters. The deployer chest will never deconstruct itself with this command.

---

![Construction robot = -1](docs/construction-robot_-1.jpg)

Cancel deconstruction or upgrades in area.

---

![Deconstruction planner = -1](docs/deconstruction-planner.jpg)

Alternative deconstruction commands that do not require a deconstruction planner in the deployer chest.

-1 = Deconstruct area.

-2 = Deconstruct the deployer chest.

-3 = Cancel deconstruction in area.

---

![Signal C = 1](docs/signal-c-1.jpg)

Copy blueprint or blueprint book. The original blueprint must be in a chest (or inserter with read hand contents) on the same circuit network as the deployer chest.

---

![Signal C = -1](docs/signal-c-2.jpg)

Delete blueprint or blueprint book.

---

X and Y signals shift the position of the construction/deconstruction order.

R signal rotates the blueprint. R = 1 = 90° clockwise, R = 2 = 180°, R = 3 = 90° counterclockwise.

To change the center of the blueprint, enable grid size (1x1 is recommended), and set an absolute reference point.

Deconstruction and upgrades use X,Y as the center of the area. This can be changed to the top left corner of the area in mod settings.

L signal is used to display debug messages (it is necessary to enable the trigger condition in the mod settings).
Each activation will display in the chat the location of the triggered deployer, the name of the blueprint and the place where the blueprint is applied (if the offset is not zero)

---

The mod also adds a Resource Scanner that can help detect places to build.

![Resource Scanner](docs/scanner.png)
