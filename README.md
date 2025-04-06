# Interactive-Map-OG20W
An interactive map of all the fixed offshore oil rigs along the Brazilian coast. Describing the potential wind generation in each of them.

The map draws each platform at it's specific location. It then generates a graph showing the wind potential at that location for the selected platform over the last 10 years. 

Due to the amount of data present in the application, it was necessary to create a database with the information about coordinates, time series of wind potential, name of platform... For the correct use of the map, it is necessary to implement the database and modify its credentials directly in the code. The database was uploaded and created using PostgresSQL. The DB can be downlodaded using this link: https://www.transfernow.net/dl/platforms_bd
The CSV contains information about coordinates, name of platform, id, and platform acronym.
