#ifndef MESSAGES_H
#define MESSAGES_H

// 18 Messages for Rehabilitation/Treatment Room Display
// Navigate with: KEY1 (Next), KEY2 (Previous), KEY0 (Back)
// Each line is exactly 16 characters (16x4 char LCD).
static const char* MSG_LIST[18][4] = {

    // === WELCOME / STATUS ===
    {" Amit Damari    ",     // Message 0: Welcome
     "                ",
     " Ido Zylberman  ",
     " 8 August 2026  "},

    {" Eytan Mann     ",     // Message 1: Session begins
     "                ",
     " Project 3420   ",
     " Best Project   "},

    // === UNIVERSITY ===
    {"      TAU       ",     // Message 2
     "                ",
     " Tel Aviv       ",
     " University     "},

    // === BREATHING EXERCISES ===
    {" Exercise 1 of 4",     // Message 3
     "                ",
     " Breathe In Deep",
     " Hold 8 Seconds "},

    {" Exercise 2 of 4",     // Message 4
     "                ",
     " Breathe Out Now",
     " Slow and Steady"},

    // === PHYSICAL EXERCISES ===
    {" Exercise 3 of 4",     // Message 5
     "                ",
     " Raise Both Arms",
     " Hold 10 Seconds"},

    {" Exercise 4 of 4",     // Message 6
     "                ",
     " Lower Arms Down",
     " Relax and Rest "},

    // === REST / BREAK ===
    {"    REST TIME   ",     // Message 7
     "                ",
     " Take a Break   ",
     " Drink Water    "},

    // === WAITING MESSAGES ===
    {" Please Wait    ",     // Message 8
     "                ",
     " Therapist Is   ",
     " On the Way     "},

    {" Your Turn Soon ",     // Message 9
     "                ",
     " Stay Seated    ",
     " We Will Call   "},

    // === INSTRUCTIONS ===
    {"  IMPORTANT     ",     // Message 10
     "                ",
     " Need Help Now  ",
     " Press Any Key  "},

    {" Do Not Leave   ",     // Message 11
     "                ",
     " Stay In Room   ",
     " Until Called   "},

    // === STATUS MESSAGES ===
    {" Session Paused ",     // Message 12
     "                ",
     " Please Wait    ",
     " Will Resume    "},

    {" Session Active ",     // Message 13
     "                ",
     " In Progress    ",
     " Do Not Disturb "},

    // === COMPLETION ===
    {" Well Done      ",     // Message 14
     "                ",
     " Exercise Set   ",
     " Completed      "},

    {" Session Done   ",     // Message 15
     "                ",
     " Please Wait    ",
     " For Discharge  "},

    // === EMERGENCY / ALERTS ===
    {" ATTENTION      ",     // Message 16
     "                ",
     " Staff Called   ",
     " Help Coming    "},

    {" System Ready   ",     // Message 17
     "                ",
     " Press Any Key  ",
     " To Begin       "}
};

#endif // MESSAGES_H
