![image](https://github.com/TokisanGames/Sky3D/blob/main/screenshots/sky3d-800px.jpg)


# Sky3D

A dynamic day/night cycle for Godot Engine 4, written in GDScript.


## Features

* Supports Godot 4.3+, Forward, Mobile, and Compatibility renderers
* Automatically rotating sun, moon, and stars, with moon phases
* Dynamic atmosphere, fog, and clouds that change with the day cycle
* Consolidated controls to manage lighting and camera exposure
* Management of game time: current time, day length, day or night


## Screenshots

![image](https://github.com/TokisanGames/Sky3D/blob/main/screenshots/oota-tree-800px.jpg)
![image](https://github.com/TokisanGames/Sky3D/blob/main/screenshots/oota-windmill-800px.jpg)


## Installation

* Clone or download the repository. 
* Open the project in Godot and run `demo/Sky3DDemo.tscn` to test it.
* Copy `addons/sky_3d` into your project `addons` directory. Create the folder if missing.
* Open `Project -> Project Settings -> Plugins` and enable the plugin. 


## Usage

* Create or open a Scene.
* Remove any existing `WorldEnvironment` node.
* Create a new `Sky3D` node.
* Customize the settings of the `Sky3D`, `Sky3D/Environment`, `TimeOfDay`, `Skydome`, `SunLight`, and `MoonLight` nodes. Some settings like light energy, color, and angle are driven by Sky3D and not directly changeable on the light nodes. You'll know if they are reset on time updates. Adjust those settings in `Sky3D` or `Skydome`.

For support, join our [Discord server](https://tokisan.com/discord).


## Credit

This plugin was originally written for Godot 3 in GDScript and C# by J. Cuéllar. The original repository was deleted. We revived it, ported the GDScript version to Godot 4, and have continued to build on it.

Developed for the Godot community by:
|||
|--|--|
| *Sky3D v2 for Godot 4* ||
| **Cory Petkovsek, Tokisan Games** | [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/twitter.png?raw=true" width="24"/>](https://twitter.com/TokisanGames) [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/github.png?raw=true" width="24"/>](https://github.com/TokisanGames) [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/www.png?raw=true" width="24"/>](https://tokisan.com/) [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/discord.png?raw=true" width="24"/>](https://tokisan.com/discord) [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/youtube.png?raw=true" width="24"/>](https://www.youtube.com/@TokisanGames)|
| **Roman Shapiro** | [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/github.png?raw=true" width="24"/>](https://github.com/rds1983)
| *TimeOfDay v1 for Godot 3* ||
| **J. Cuéllar** | [<img src="https://github.com/dmhendricks/signature-social-icons/blob/master/icons/round-flat-filled/35px/twitter.png?raw=true" width="24"/>](https://twitter.com/JayKuellar) 

And contributors shown in the right sidebar of the github repository.


## License

This addon has been released under the [MIT License](LICENSE.txt).

If using the stars asset, you must [credit the author](https://github.com/TokisanGames/Sky3D/blob/main/addons/sky_3d/assets/thirdparty/textures/milkyway/LICENSE.md).
