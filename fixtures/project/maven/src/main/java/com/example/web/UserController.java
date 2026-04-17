package com.example.web;

import java.util.Optional;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import com.example.Service;
import com.example.model.User;
import com.example.repository.UserRepository;

@RestController
public class UserController {

    @Autowired
    private UserRepository repo;

    @Autowired
    private Service service;

    @GetMapping("/users/{id}")
    public Optional<User> get(@PathVariable long id) {
        return repo.findById(id);
    }
}
